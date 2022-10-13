// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";
import "./HubErrors.sol";

contract Hub is HubSetters, HubGetters, HubStructs, HubMessages, HubEvents {
    constructor(address wormhole_, address tokenBridge_, address mockPythAddress_, uint8 consistencyLevel_) {
        setOwner(_msgSender());
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
        setPyth(mockPythAddress_);

        setConsistencyLevel(consistencyLevel_);

    }

    function registerAsset(address assetAddress, uint256 collateralizationRatio, uint256 reserveFactor, bytes32 pythId, uint8 decimals) public {
        require(msg.sender == owner());

        // check if asset is already registered (potentially write a getter for the assetInfos map)
        AssetInfo registered_info = getAssetInfo(assetAddress);
        if (registered_info.isValue) {
            // If not, update the 'allowList' array (write a setter for the allowList array)
            allowAsset(assetAddress);

            // update the asset info map
            AssetInfo info = AssetInfo({
                collaterizationRatio: collateralizationRatio,
                reserveFactor: reserveFactor,
                pythId: pythId,
                decimals: decimals,
                isValue: true
            });

            registerAssetInfo(assetAddress, info);
        }
    }

    function registerSpoke(uint16 chainId, address spokeContractAddress) public {
        require(msg.sender == owner());
        registerSpokeContract(chainId, spokeContractAddress);
    }

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {
        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

    function computeSourceInterestFactor(
        uint256 secondsElapsed, 
        uint256 deposited, 
        uint256 borrowed, 
        InterestRateModel interestRateModel
    ) internal view returns (uint256) {
        if (deposited == 0) {
            return 0;
        }

        return
            (secondsElapsed * 
                (interestRateModel.rateIntercept + (interestRateModel.rateCoefficientA * borrowed) / deposited)) /
            365 /
            24 /
            60 /
            60;
    }

    function updateAccrualIndices(address[] assetAddresses) internal {
        for(uint i=0; i<assetAddresses.length; i++){
            address assetAddress = assetAddresses[i];

            uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
            uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;

            uint256 deposited = getTotalAssetsDeposited(assetAddress);
            uint256 borrowed = getTotalAssetsBorrowed(assetAddress);

            setLastActivityBlockTimestamp(assetAddress, block.timestamp);

            InterestRateModel interestRateModel = getInterestRateModel(assetAddress);

            uint256 interestFactor = computeSourceInterestFactor(
                secondsElapsed,
                deposited,
                borrowed,
                interestRateModel
            );

            AccrualIndices accrualIndices = getInterestAccrualIndices(assetAddress);
            accrualIndices.borrowed += interestFactor;
            accrualIndices.deposited += (interestFactor * borrowed) / deposited;
            accrualIndices.lastBlock = block.timestamp;

            setInterestAccrualIndex(assetAddress, accrualIndices);
        }
    }

    function completeDeposit(bytes calldata encodedMessage) public {

        DepositMessage memory params = decodeDepositMessage(getWormholePayload(encodedMessage));

        address depositor = params.header.sender;

        checkValidAddresses(params.assetAddresses);

        // update the interest accrual indices
        updateAccrualIndices(params.assetAddresses);

        // for each asset, calculate the normalized amount and store in the vault
        // for each asset, update the global contract state with normalized amount (??)
        for(uint i=0; i<params.assetAddresses.length; i++){
            VaultAmount vault = getVaultAmounts(depositor, params.assetAddress[i]);
            VaultAmount globalAmounts = getGlobalAmounts(params.assetAddress[i]);

            AccrualIndices indices = getInterestAccrualIndices(params.assetAddresses[i]);

            uint256 normalizedDeposit = normalizeAmount(params.assetAmounts[i].deposited, indices.deposited);

            vault.deposited += normalizedDeposit;
            globalAmounts.deposited += normalizedDeposit; // params.assetAmounts[i];

            setVaultAmounts(depositor, params.assetAddresses[i], vault);
            setGlobalAmounts(params.assetAddresses[i], globalAmounts);

            // TODO: token transfers--directly mint to the lending protocol
            SafeERC20.safeTransferFrom(
                params.assetAddresses[i],
                ,
                address(this),
                params.assetAmounts[i]
            );
        }        
    }

    function completeWithdraw(bytes calldata encodedMessage) public {

        WithdrawMessage memory params = decodeWithdrawMessage(getWormholePayload(encodedMessage));

        address borrower = params.header.sender;

        checkValidAddresses(params.assetAddresses);

        // get prices for assets
        uint64[params.assetAddresses.length] prices;
        for(uint i=0; i<params.assetAddresses.length; i++){
            prices[i] = getOraclePrices(params.assetAddresses[i]);
        }

        // recheck if withdraw is valid given up to date prices? bc the prices can move in the time for VAA to come
        allowedToWithdraw(borrower, params.assetAddresses, params.assetAmounts, prices);

        // update the interest accrual indices
        updateAccrualIndices(params.assetAddresses);

        // for each asset update amounts for vault and global
        for(uint i=0; i<params.assetAddresses.length; i++){
            uint256 amount = params.assetAmounts[i];
            AccrualIndices indices = getInterestAccrualIndices(params.assetAddress[i]);

            uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
            // update state for vault
            VaultAmount vaultAmounts = getVaultAmounts(borrower, params.assetAddresses[i]);
            vaultAmounts.borrowed += normalizedAmount;
            // update state for global
            VaultAmount globalAmounts = getGlobalAmounts(params.assetAddresses[i]);
            globalAmounts.borrowed += normalizedAmount;
        }
        

        // NOTE: interest payment handled by normalization within this function

        // TODO: token transfers (will fail if not enough tokens)

    }

    function completeBorrow(bytes calldata encodedMessage) public {
        // TODO: check if borrow is valid given up to date prices?

        // TODO: for each asset, calculate the normalized amount that can be borrowed, fail if not as much as requested

        // TODO: update the contract state (assets borrowed)

        // TODO: token transfers
    }

    function completeRepay(bytes calldata encodedMessage) public {
        // TODO: for each asset check if allowed

        // TODO: update the interest accrual indices

        // TODO: for each asset, calculate the normalized amount and store in the vault


        // TODO: update the contract state (assets deposited)

        // TODO: token transfers (do you need this here? you should probably just transfer tokens directly to the lending protocol via relayer)
    }

    function completeLiquidation(bytes calldata encdoedMessage) public {
        // TODO: for each repay asset check if allowed

        // TODO: update the interest accrual indices

        // TODO: for each repay asset, calculate the normalized amount and store in the vault

        // TODO: for each receipt asset, calculate the normalized amount that can be removed, fail if not as much as requested

        // TODO: do the Pyth math to figure out if vault still underwater and the requested amounts still valid

        // TODO: update the contract state

        // TODO: token transfers

    }

    function repay() public {}

    function liquidate(address vault, address[] memory tokens) public {}

    function sendWormholeMessage(bytes memory payload)
        internal
        returns (uint64 sequence)
    {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function getWormholePayload(bytes calldata encodedMessage) internal returns (bytes memory) {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        verifySenderIsSpoke(parsed.emitterChainId, address(uint160(bytes20(parsed.emitterAddress))));

        require(!messageHashConsumed(parsed.hash), "message already confused");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    } 

    
}