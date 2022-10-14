// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";

contract Hub is HubStructs, HubMessages, HubSetters, HubGetters {
    constructor(address wormhole_, address tokenBridge_, address mockPythAddress_, uint8 consistencyLevel_) {
        setOwner(_msgSender());
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
        setPyth(mockPythAddress_);

        setConsistencyLevel(consistencyLevel_);
    }

    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatio,
        uint256 reserveFactor,
        bytes32 pythId,
        uint8 decimals
    ) public {
        require(msg.sender == owner());

        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(!registered_info.exists, "Asset already registered");

        allowAsset(assetAddress);

        AssetInfo memory info = AssetInfo({
            collateralizationRatio: collateralizationRatio,
            reserveFactor: reserveFactor,
            pythId: pythId,
            decimals: decimals,
            exists: true
        });

        registerAssetInfo(assetAddress, info);
    }

    function registerSpoke(uint16 chainId, address spokeContractAddress) public {
        require(msg.sender == owner());
        registerSpokeContract(chainId, spokeContractAddress);
    }

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
        uint256 borrowed = getTotalAssetsBorrowed(assetAddress);

        setLastActivityBlockTimestamp(assetAddress, block.timestamp);

        InterestRateModel memory interestRateModel = getInterestRateModel(assetAddress);

        uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);

        AccrualIndices memory accrualIndices = getInterestAccrualIndices(assetAddress);
        accrualIndices.borrowed += interestFactor;
        accrualIndices.deposited += (interestFactor * borrowed) / deposited;
        accrualIndices.lastBlock = block.timestamp;

        setInterestAccrualIndices(assetAddress, accrualIndices);
    }

    /*
    function updateAccrualIndices(address[] assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address assetAddress = assetAddresses[i];

            updateAccrualIndices(assetAddress);
        }
    }*/

    function completeDeposit(bytes calldata encodedMessage) public {

        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        DepositPayload memory params = decodeDepositPayload(vmPayload);

        deposit(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeWithdraw(bytes calldata encodedMessage) public {

        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        WithdrawPayload memory params = decodeWithdrawPayload(vmPayload);

        withdraw(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeBorrow(bytes calldata encodedMessage) public {
        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        BorrowPayload memory params = decodeBorrowPayload(vmPayload);

        borrow(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeRepay(bytes calldata encodedMessage) public {

        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        RepayPayload memory params = decodeRepayPayload(vmPayload);
        
        repay(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function deposit(address depositor, address assetAddress, uint256 amount) internal {
        // TODO: What to do if this fails?
        checkValidAddress(assetAddress);

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        // calculate the normalized amount and store in the vault
        // update the global contract state with normalized amount
        VaultAmount memory vault = getVaultAmounts(depositor, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited);

        vault.deposited += normalizedDeposit;
        globalAmounts.deposited += normalizedDeposit;

        setVaultAmounts(depositor, assetAddress, vault);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

    

    function withdraw(address withdrawer, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // recheck if withdraw is valid given up to date prices? bc the prices can move in the time for VAA to come
        require(allowedToWithdraw(withdrawer, assetAddress, amount), "Not enough in vault");

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(withdrawer, assetAddress);
        vaultAmounts.deposited -= normalizedAmount;
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.deposited -= normalizedAmount;

        setVaultAmounts(withdrawer, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

    function borrow(address borrower, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // recheck if borrow is valid given up to date prices? bc the prices can move in the time for VAA to come
        require(allowedToBorrow(borrower, assetAddress, amount), "Not enough in vault");

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(borrower, assetAddress);
        vaultAmounts.borrowed += normalizedAmount;
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed -= normalizedAmount;

        setVaultAmounts(borrower, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);

        // TODO: token transfers
    }

    function repay(address repayer, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        // calculate the normalized amount and store in the vault and global
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(repayer, assetAddress);
        vaultAmounts.borrowed -= normalizedAmount;
        // update global state
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed -= normalizedAmount;

        // TODO: token transfers (do you need this here? you should probably just transfer tokens directly to the lending protocol via relayer)
    
    }

    /*
    // TODO: rename "completeLiquidation" to Liquidate bc all liqs from hub...
    function completeLiquidation(bytes calldata encodedMessage) public {
        LiquidationPayload memory params = decodeLiquidationPayload(getWormholePayload(encodedMessage));

        RepayPayload memory params = decodeRepayPayload(vmPayload);

        address repayer = params.header.sender;
        address assetAddress = params.assetAddress;
        uint256 amount = params.assetAmount;

        address[] memory assetAddresses = new address[](1);
        assetAddresses[0] = assetAddress;

        checkValidAddresses(assetAddresses);

        // update the interest accrual indices
        updateAccrualIndices(assetAddresses);

        // for asset update amounts for vault and global
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);
        uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);

        require(amount <= normalizedAmount, "Cannot repay more than borrowed");

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(repayer, assetAddress);
        vaultAmounts.borrowed -= normalizedAmount;
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed -= normalizedAmount;

        setVaultAmounts(repayer, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

    // TODO: rename "completeLiquidation" to Liquidate bc all liqs from hub...
    function completeLiquidation(bytes calldata encodedMessage) public {
        LiquidationPayload memory params = decodeLiquidationPayload(getWormholePayload(encodedMessage));

        // address liquidator = params.header.sender;
        // address vault = params.vault;

        // checkValidAddresses(params.assetRepayAddresses);
        // checkValidAddresses(params.assetReceiptAddresses);

        // // get prices for assets used for repay
        // uint64[params.assetRepayAddresses.length] memory pricesRepay;
        // for (uint256 i = 0; i < params.assetAddresses.length; i++) {
        //     pricesRepay[i] = getOraclePrices(params.assetRepayAddresses[i]);
        // }
        // // get prices for assets received
        // uint64[params.assetReceiptAddresses.length] memory pricesReceipt;
        // for (uint256 i = 0; i < params.assetAddresses.length; i++) {
        //     pricesReceipt[i] = getOraclePrices(params.assetReceiptAddresses[i]);
        // }

        // // TODO: check if vault under water
        // // TODO: check if this repayment is valid (i.e. notional_repaid < notional_received < notional_repaid * liquidation_bonus)
        // allowedToLiquidate(
        //     vault,
        //     params.assetRepayAddresses,
        //     params.assetRepayAmounts,
        //     pricesRepay,
        //     params.assetReceiptAddresses,
        //     params.assetReceiptAmounts,
        //     pricesReceipt
        // );

        // // update the interest accrual indices
        // updateAccrualIndices(params.assetRepayAddresses);
        // updateAccrualIndices(params.assetReceiptAddresses);

        // // for each repay asset update amounts for vault and global
        // for (uint256 i = 0; i < params.assetRepayAddresses.length; i++) {
        //     address assetAddress = params.assetRepayAddresses[i];
        //     uint256 amount = params.assetRepayAmounts[i];

        //     AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        //     uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
        //     // TODO: how to update state for vault??
        //     // TODO: how to update state for global??
        // }

        // // for each received asset update amounts for vault and global
        // for (uint256 i = 0; i < params.assetReceiptAddresses.length; i++) {
        //     address assetAddress = params.assetReceiptAddresses[i];
        //     uint256 amount = params.assetReceiptAmounts[i];

        //     AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        //     uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
        //     // TODO: how to update state for vault??
        //     // TODO: how to update state for global??
        // }

        // // TODO: for each repay asset check if allowed

        // // TODO: update the interest accrual indices

        // // TODO: for each repay asset, calculate the normalized amount and store in the vault

        // // TODO: token transfers
    }

     function liquidate(address vault, address[] memory tokens) public {}
    */


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

        verifySenderIsSpoke(parsed.emitterChainId, address(uint160(bytes20(parsed.emitterAddress))));

        require(!messageHashConsumed(parsed.hash), "message already confused");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    }
}
