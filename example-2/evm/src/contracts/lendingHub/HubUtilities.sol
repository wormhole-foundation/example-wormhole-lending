// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IMockPyth.sol";
import "./HubStructs.sol";
import "./HubState.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";

import "forge-std/console.sol";

contract HubUtilities is Context, HubStructs, HubState, HubGetters, HubSetters {
    /** 
    * Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued). 
    * 
    * @param {uint256} denormalizedAmount - The true amount of an asset
    * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision(). 
    * So, (interestAccrualIndex/interestAccrualIndexPrecision) represents the interest accrued (this is initialized to 1 at the start of the protocol)
    * @return {uint256} The normalized amount of the asset
    */
    function normalizeAmount(uint256 denormalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (denormalizedAmount * getInterestAccrualIndexPrecision()) / interestAccrualIndex;
    }

    /** 
    * Similar to 'normalizeAmount', takes a normalized value (amount of an asset) and denormalizes it.  
    * 
    * @param {uint256} normalizedAmount - The normalized amount of an asset
    * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision(). 
    * @return {uint256} The true amount of the asset
    */
    function denormalizeAmount(uint256 normalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (normalizedAmount * interestAccrualIndex) / getInterestAccrualIndexPrecision();
    }

    /** 
    * Denormalize both the 'deposited' and 'borrowed' values in the 'VaultAmount' struct, using the interest accrual indices corresponding 
    * to deposit and borrow for the asset at address 'assetAddress'. 
    * @param {VaultAmount} va - The amount deposited and borrowed for an asset in a vault. Stored as two uint256s. 
    * @param {address} assetAddress - The address of the asset that 'va' is showing the amounts of. 
    * @return {uint256} The denormalized amounts of 'assetAddress' that have been deposited and borrowed in the 'va' vault
    */
    function denormalizeVaultAmount(VaultAmount memory va, address assetAddress) internal view returns (VaultAmount memory) {
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);
        uint256 denormalizedDeposited = denormalizeAmount(va.deposited, indices.deposited);
        uint256 denormalizedBorrowed = denormalizeAmount(va.borrowed, indices.borrowed);
        return VaultAmount({
            deposited: denormalizedDeposited,
            borrowed: denormalizedBorrowed
        });

    }

    /** 
    * Get the price, through Pyth, of the asset at address assetAddress
    * @param {address} assetAddress - The address of the relevant asset
    * @return {uint64} The price (in USD) of the asset, from Pyth 
    * TODO: Elaborate on the above line 
    */
    function getOraclePrices(address assetAddress) internal view returns (uint64) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        // getting oracle price via hubgetters fn (TODO: remove if we get oracle contract up and running)
        Price memory oraclePrice = getOraclePrice(assetInfo.pythId);
        // IMockPyth.PriceFeed memory feed = mockPyth().queryPriceFeed(assetInfo.pythId);

        // sanity check the price feeds
        require(oraclePrice.price > 0, "negative prices detected");
        // require(feed.price.price > 0, "negative prices detected");

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return uint64(oraclePrice.price);
        // return uint64(feed.price.price);
    }

    /** 
    * Using the pyth prices, get the total price of the assets deposited into the vault, and 
    * total price of the assets borrowed from the vault (multiplied by their respecetive collatorization ratios) 
    * @param {address} vaultOwner - The address of the owner of the vault
    * @return {(uint256, uint256)} The total price of the assets deposited into and borrowed from the vault, respectively
    */
    function getVaultEffectiveNotionals(address vaultOwner) internal view returns (uint256, uint256) {

        uint256 effectiveNotionalDeposited = 0;
        uint256 effectiveNotionalBorrowed = 0;

        address[] memory allowList = getAllowList();
        for(uint i=0; i<allowList.length; i++) {
            address asset = allowList[i];

            
            VaultAmount memory normalizedAmounts = getVaultAmounts(vaultOwner, asset);

            uint64 price = getOraclePrices(asset);
            
            AssetInfo memory assetInfo = getAssetInfo(asset);

            AccrualIndices memory indices = getInterestAccrualIndices(asset);
            
            uint256 denormalizedDeposited = denormalizeAmount(normalizedAmounts.deposited, indices.deposited);
            uint256 denormalizedBorrowed = denormalizeAmount(normalizedAmounts.borrowed, indices.borrowed);

            effectiveNotionalDeposited += denormalizedDeposited * price * 10 ** (getMaxDecimals() - assetInfo.decimals); // / (10**assetInfo.decimals);

            effectiveNotionalBorrowed += denormalizedBorrowed * assetInfo.collateralizationRatio * price * 10 ** (getMaxDecimals() - assetInfo.decimals) / getCollateralizationRatioPrecision(); 

        }    

        return (effectiveNotionalDeposited, effectiveNotionalBorrowed);
    }


    /** 
    * Check if vaultOwner is allowed to withdraw assetAmount of assetAddress from their vault
    * @param {address} vaultOwner - The address of the owner of the vault
    * @param {address} assetAddress - The address of the relevant asset
    * @param {uint256} assetAmount - The amount of the relevant asset
    * @return {bool} True or false depending on if this withdrawal keeps the vault at a nonnegative notional value (worth >= $0 according to Pyth prices) 
    * (where the borrow values are multiplied by their collateralization ratio) and also if there is enough asset in the vault to complete the withdrawal
    * and also if there is enough asset in the total reserve of the protocol to complete the withdrawal
    */ // TODO: cycle through all assets in the vault
    function allowedToWithdraw(address vaultOwner, address assetAddress, uint256 assetAmount) internal view returns (bool, bool, bool) {       

        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint64 price = getOraclePrices(assetAddress);

        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vaultOwner); 

        VaultAmount memory amounts = denormalizeVaultAmount(getVaultAmounts(vaultOwner, assetAddress), assetAddress);
        
        VaultAmount memory globalAmounts = denormalizeVaultAmount(getGlobalAmounts(assetAddress), assetAddress);

        return ((amounts.deposited - amounts.borrowed >= assetAmount), (globalAmounts.deposited - globalAmounts.borrowed >= assetAmount), ((vaultDepositedValue - vaultBorrowedValue)*(10**assetInfo.decimals) >= assetAmount * price * (10 ** getMaxDecimals()))); 
    }

    /** 
    * Check if vaultOwner is allowed to borrow assetAmount of assetAddress from their vault
    * @param {address} vaultOwner - The address of the owner of the vault
    * @param {address} assetAddress - The address of the relevant asset
    * @param {uint256} assetAmount - The amount of the relevant asset
    * @return {bool} True or false depending on if this borrow keeps the vault at a nonnegative notional value (worth >= $0 according to Pyth prices) 
    * (where the borrow values are multiplied by their collateralization ratio) and also if there is enough asset in the total reserve of the protocol to complete the borrow
    */
    function allowedToBorrow(address vaultOwner, address assetAddress, uint256 assetAmount) internal view returns (bool, bool) {       
        
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint64 price = getOraclePrices(assetAddress);
     
        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vaultOwner);
     
        VaultAmount memory globalAmounts = denormalizeVaultAmount(getGlobalAmounts(assetAddress), assetAddress);
        
        return ((globalAmounts.deposited - globalAmounts.borrowed >= assetAmount), ((vaultDepositedValue - vaultBorrowedValue)*10**(assetInfo.decimals) >= assetAmount * price * assetInfo.collateralizationRatio * (10**getMaxDecimals()) / getCollateralizationRatioPrecision() ));

    }

    /** 
    * Check if vaultOwner is allowed to, for each i, repay assetRepayAmounts[i] of the asset at assetRepayAddresses[i] to the vault at 'vault', 
    * and receive from the vault, for each i, assetReceiptAmounts[i] of the asset at assetReceiptAddresses[i]. Uses the Pyth prices to see if this liquidation should be allowed
    * @param {address} vault - The address of the owner of the vault
    * @param {address} assetRepayAddresses - The array of addresses of the assets being repayed 
    * @param {uint256} assetRepayAmounts - The array of amounts of each asset in assetRepayAddresses
    * @param {address} assetReceiptAddresses - The array of addresses of the assets being repayed 
    * @param {uint256} assetReceiptAmounts - The array of amounts of each asset in assetRepayAddresses
    * @return {bool} True or false depending on if this liquidation attempt is allowed
    */
    function allowedToLiquidate(address vault, address[] memory assetRepayAddresses, uint256[] memory assetRepayAmounts, address[] memory assetReceiptAddresses, uint256[] memory assetReceiptAmounts) internal view returns (bool) {
        
        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vault); 

        require(vaultDepositedValue < vaultBorrowedValue, "vault not underwater");
        
        uint256 notionalRepaid = 0;
        uint256 notionalReceived = 0;

        // get notional repaid
        for(uint i=0; i<assetRepayAddresses.length; i++){
            address asset = assetRepayAddresses[i];
            uint256 amount = assetRepayAmounts[i];

            uint64 price = getOraclePrices(asset);

            AssetInfo memory assetInfo = getAssetInfo(asset);

            notionalRepaid += amount * price * 10 ** (getMaxDecimals() - assetInfo.decimals); 
        }

        // get notional received
        for(uint i=0; i<assetReceiptAddresses.length; i++){
            address asset = assetReceiptAddresses[i];
            uint256 amount = assetReceiptAmounts[i];

            uint64 price = getOraclePrices(asset);

            AssetInfo memory assetInfo = getAssetInfo(asset);

            notionalReceived += amount * price * 10 ** (getMaxDecimals() - assetInfo.decimals); 
        }

        // safety check to ensure liquidator doesn't play themselves
        require(notionalReceived >= notionalRepaid, "Liquidator receipt less than amount they repaid");

        // check if notional received <= notional repaid * max liquidation bonus
        uint256 maxLiquidationBonus = getMaxLiquidationBonus();

        return (notionalReceived <= maxLiquidationBonus * notionalRepaid / getCollateralizationRatioPrecision());
    }

    /**
    * Check if an address has been registered on the Hub yet (through the registerAsset function)
    * Errors out if assetAddress has not been registered yet
    * @param assetAddress - The address to be checked
    */
    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(registered_info.exists, "Unregistered asset");
    }

    // TODO: Write docstrings for these functions

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {

        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

    function computeSourceInterestFactor (
        uint256 secondsElapsed,
        uint256 deposited,
        uint256 borrowed,
        InterestRateModel memory interestRateModel
    ) internal pure returns (uint256) {
        if (deposited == 0) {
            return 0;
        }

        return (
            secondsElapsed
                * (interestRateModel.rateIntercept + (interestRateModel.rateCoefficientA * borrowed) / deposited)
        ) / 365 / 24 / 60 / 60;
    }

    function updateAccrualIndices(address assetAddress) internal {
        uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
        uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;

        uint256 deposited = getTotalAssetsDeposited(assetAddress);
        AccrualIndices memory accrualIndices = getInterestAccrualIndices(assetAddress);

        if(secondsElapsed == 0) {
            // no need to update anything
            return;
        }

        accrualIndices.lastBlock = block.timestamp;

        if(deposited == 0) {
            // avoid divide by 0 due to 0 deposits
            return;
        }

        uint256 borrowed = getTotalAssetsBorrowed(assetAddress);

        setLastActivityBlockTimestamp(assetAddress, block.timestamp);

        InterestRateModel memory interestRateModel = getInterestRateModel(assetAddress);

        uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);

        accrualIndices.borrowed += interestFactor;
        accrualIndices.deposited += (interestFactor * borrowed) / deposited;

        setInterestAccrualIndices(assetAddress, accrualIndices);
    }

    function transferTokens(address receiver, address assetAddress, uint256 amount) internal {
        //tokenBridge().transferTokensWithPayload(assetAddress, amount, recipientChain, recipient, nonce, payload);
    }

    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function getWormholePayload(bytes calldata encodedMessage) internal returns (bytes memory) {
        (IWormhole.VM memory parsed, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        verifySenderIsSpoke(parsed.emitterChainId, address(uint160(uint256(parsed.emitterAddress))));

        require(!messageHashConsumed(parsed.hash), "message already consumed");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    }

    function getTransferPayload(bytes memory encodedMessage) internal returns (bytes memory payload) {
        payload = tokenBridge().completeTransferWithPayload(encodedMessage);

        // do some stuff
        
    }

    /*
    function updateAccrualIndices(address[] assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address assetAddress = assetAddresses[i];

            updateAccrualIndices(assetAddress);
        }
    }*/





    // /*
    // function checkValidAddresses(address[] calldata assetAddresses) internal view {
    //     mapping(address => bool) memory observedAssets;

    //     for(uint i=0; i<assetAddresses.length; i++){
    //         address assetAddress = assetAddresses[i];
    //         // check if asset address is allowed
    //         AssetInfo memory registered_info = getAssetInfo(assetAddress);
    //         require(registered_info.isValue, "Unregistered asset");

    //         // check if each address is unique
    //         // require(!observedAssets[assetAddress], "Repeated asset");

    //         // observedAssets[assetAddress] = true;
    //     }
    // }*/
}