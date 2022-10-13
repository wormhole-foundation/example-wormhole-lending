// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";

contract Hub is  HubStructs, HubMessages, HubSetters, HubGetters {
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

        return (
            secondsElapsed
                * (interestRateModel.rateIntercept + (interestRateModel.rateCoefficientA * borrowed) / deposited)
        ) / 365 / 24 / 60 / 60;
    }

    function updateAccrualIndices(address[] assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address assetAddress = assetAddresses[i];

            uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
            uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;

            uint256 deposited = getTotalAssetsDeposited(assetAddress);
            uint256 borrowed = getTotalAssetsBorrowed(assetAddress);

            setLastActivityBlockTimestamp(assetAddress, block.timestamp);

            InterestRateModel interestRateModel = getInterestRateModel(assetAddress);

            uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);

            AccrualIndices accrualIndices = getInterestAccrualIndices(assetAddress);
            accrualIndices.borrowed += interestFactor;
            accrualIndices.deposited += (interestFactor * borrowed) / deposited;
            accrualIndices.lastBlock = block.timestamp;

            setInterestAccrualIndex(assetAddress, accrualIndices);
        }
    }

    function completeDeposit(bytes calldata encodedMessage) public {
        // DepositPayload memory params = decodeDepositPayload(getWormholePayload(encodedMessage));
        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        DepositPayload memory params = decodeDepositPayload(vmPayload);

        address depositor = params.header.sender;
        address assetAddress = params.assetAddress;
        uint256 amount = params.assetAmount;

        address[] assetAddresses = new address[](1);
        assetAddresses[0] = assetAddress;

        // TODO: What to do if this fails?
        checkValidAddresses([assetAddress]);

        // update the interest accrual indices
        updateAccrualIndices([assetAddress]);

        // calculate the normalized amount and store in the vault
        // update the global contract state with normalized amount

        VaultAmount vault = getVaultAmounts(depositor, assetAddress);
        VaultAmount globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices indices = getInterestAccrualIndices([assetAddress]);

        uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited);

        vault.deposited += normalizedDeposit;
        globalAmounts.deposited += normalizedDeposit; // params.assetAmounts[i];

        setVaultAmounts(depositor, assetAddress, vault);
        setGlobalAmounts(assetAddress, globalAmounts);

        // TODO: token transfers--directly mint to the lending protocol
        /*SafeERC20.safeTransferFrom(
                params.assetAddresses[i],
                ,
                address(this),
                params.assetAmounts[i]
            );*/
    }

    function completeWithdraw(bytes calldata encodedMessage) public {
        WithdrawPayload memory params = decodeWithdrawPayload(getWormholePayload(encodedMessage));

        address borrower = params.header.sender;

        checkValidAddresses(params.assetAddresses);

        // get prices for assets
        uint64[params.assetAddresses.length] prices;
        for (uint256 i = 0; i < params.assetAddresses.length; i++) {
            prices[i] = getOraclePrices(params.assetAddresses[i]);
        }

        // recheck if withdraw is valid given up to date prices? bc the prices can move in the time for VAA to come
        allowedToWithdraw(borrower, params.assetAddresses, params.assetAmounts, prices);

        // update the interest accrual indices
        updateAccrualIndices(params.assetAddresses);

        // for each asset update amounts for vault and global
        for (uint256 i = 0; i < params.assetAddresses.length; i++) {
            address assetAddress = params.assetAddresses[i];
            uint256 amount = params.assetAmounts[i];

            AccrualIndices indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
            // update state for vault
            VaultAmount vaultAmounts = getVaultAmounts(borrower, assetAddress);
            vaultAmounts.borrowed += normalizedAmount;
            // update state for global
            VaultAmount globalAmounts = getGlobalAmounts(assetAddress);
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
        RepayPayload memory params = decodeRepayPayload(getWormholePayload(encodedMessage));

        address repayer = params.header.sender;

        checkValidAddresses(params.assetAddresses);

        // update the interest accrual indices
        updateAccrualIndices(params.assetAddresses);

        // TODO: for each asset, calculate the normalized amount and store in the vault and global
        for (uint256 i = 0; i < params.assetAddresses.length; i++) {
            address assetAddress = params.assetAddresses[i];
            uint256 amount = params.assetAmounts[i];

            AccrualIndices indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);
            // update state for vault
            VaultAmount vaultAmounts = getVaultAmounts(borrower, assetAddress);
            vaultAmounts.borrowed -= normalizedAmount;
            // update global state
            VaultAmount globalAmounts = getGlobalAmounts(assetAddress);
            globalAmounts.borrowed -= normalizedAmount;
        }

        // TODO: token transfers (do you need this here? you should probably just transfer tokens directly to the lending protocol via relayer)
    }

    // TODO: rename "completeLiquidation" to Liquidate bc all liqs from hub...
    function completeLiquidation(bytes calldata encodedMessage) public {
        LiquidationPayload memory params = decodeLiquidationPayload(getWormholePayload(encodedMessage));

        address liquidator = params.header.sender;
        address vault = params.vault;

        checkValidAddresses(params.assetRepayAddresses);
        checkValidAddresses(params.assetReceiptAddresses);

        // get prices for assets used for repay
        uint64[params.assetRepayAddresses.length] pricesRepay;
        for (uint256 i = 0; i < params.assetAddresses.length; i++) {
            pricesRepay[i] = getOraclePrices(params.assetRepayAddresses[i]);
        }
        // get prices for assets received
        uint64[params.assetReceiptAddresses.length] pricesReceipt;
        for (uint256 i = 0; i < params.assetAddresses.length; i++) {
            pricesReceipt[i] = getOraclePrices(params.assetReceiptAddresses[i]);
        }

        // TODO: check if vault under water
        // TODO: check if this repayment is valid (i.e. notional_repaid < notional_received < notional_repaid * liquidation_bonus)
        allowedToLiquidate(
            vault,
            params.assetRepayAddresses,
            params.assetRepayAmounts,
            pricesRepay,
            params.assetReceiptAddresses,
            params.assetReceiptAmounts,
            pricesReceipt
        );

        // update the interest accrual indices
        updateAccrualIndices(params.assetRepayAddresses);
        updateAccrualIndices(params.assetReceiptAddresses);

        // for each repay asset update amounts for vault and global
        for (uint256 i = 0; i < params.assetRepayAddresses.length; i++) {
            address assetAddress = params.assetRepayAddresses[i];
            uint256 amount = params.assetRepayAmounts[i];

            AccrualIndices indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
            // TODO: how to update state for vault??
            // TODO: how to update state for global??
        }

        // for each received asset update amounts for vault and global
        for (uint256 i = 0; i < params.assetReceiptAddresses.length; i++) {
            address assetAddress = params.assetReceiptAddresses[i];
            uint256 amount = params.assetReceiptAmounts[i];

            AccrualIndices indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
            // TODO: how to update state for vault??
            // TODO: how to update state for global??
        }

        // TODO: for each repay asset check if allowed

        // TODO: update the interest accrual indices

        // TODO: for each repay asset, calculate the normalized amount and store in the vault

        // TODO: token transfers
    }

    function repay() public {}

    function liquidate(address vault, address[] memory tokens) public {}

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
