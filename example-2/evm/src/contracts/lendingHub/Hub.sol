// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "../HubSpokeStructs.sol";
import "../HubSpokeMessages.sol";
import "./HubGetters.sol";
import "./HubChecks.sol";
import "./HubWormholeUtilities.sol";

contract Hub is HubSpokeStructs, HubSpokeMessages, HubGetters, HubSetters, HubWormholeUtilities, HubChecks {
    /**
     * @notice Hub constructor - Initializes a new hub with given parameters
     * 
     * @param wormhole: Address of the Wormhole contract on the Hub chain
     * @param tokenBridge: Address of the TokenBridge contract on the Hub chain
     * @param consistencyLevel: Desired level of finality the Wormhole guardians will reach before signing the messages
     * Note: consistencyLevel = 200 will result in an instant message, while all other values will wait for finality
     * Recommended finality levels can be found here: https://book.wormhole.com/reference/contracts.html
     *
     * @param pythAddress: Address of the Pyth oracle on the Hub chain
     * @param oracleMode: Variable that should be 0 and exists only for testing purposes.
     * If oracleMode = 0, Hub uses Pyth; if 1, Hub uses a mock Pyth for testing, and if 2, Hub uses a dummy oracle that can be manually set
     * @param priceStandardDeviations: priceStandardDeviations = (psd * priceStandardDeviationsPrecision), where psd is the number of standard deviations that we use for our price intervals in calculations relating to allowing withdraws, borrows, or liquidations
     * @param priceStandardDeviationsPrecision: A precision number that allows us to represent our desired noninteger price standard deviation as an integer (specifically, psd = priceStandardDeviations/priceStandardDeviationsPrecision)
     *
     * @param maxLiquidationBonus: maxLiquidationBonus = (mlb * collateralizationRatioPrecision), where mlb is the multiplier such that if the fair value of a liquidator's repayed assets is v, the assets they receive can have a maximum of mlb*v in fair value. Fair value is computed using Pyth prices.
     * @param maxLiquidationPortion: maxLiquidationPortion = (mlp * maxLiquidationPortionPrecision), where mlp is the maximum fraction of the borrowed value vault that a liquidator can liquidate at once.
     * @param maxLiquidationPortionPrecision: A precision number that allows us to represent our desired noninteger max liquidation portion mlp as an integer (specifically, mlp = maxLiquidationPortion/maxLiquidationPortionPrecision)
     *
     * @param interestAccrualIndexPrecision: A precision number that allows us to represent our noninteger interest accrual indices as integers; we store each index as its true value multiplied by interestAccrualIndexPrecision
     * @param collateralizationRatioPrecision: A precision number that allows us to represent our noninteger collateralization ratios as integers; we store each ratio as its true value multiplied by collateralizationRatioPrecision
     */
    constructor(
        /* Wormhole Information */
        address wormhole,
        address tokenBridge,
        uint8 consistencyLevel,
        /* Pyth Information */
        address pythAddress,
        uint8 oracleMode,
        uint64 priceStandardDeviations,
        uint64 priceStandardDeviationsPrecision,
        /* Liquidation Information */
        uint256 maxLiquidationBonus,
        uint256 maxLiquidationPortion,
        uint256 maxLiquidationPortionPrecision,
        uint256 interestAccrualIndexPrecision,
        uint256 collateralizationRatioPrecision
    ) {
        require(interestAccrualIndexPrecision <= 10 ** 6);
        require(collateralizationRatioPrecision <= 10 ** 6);
        require(maxLiquidationPortionPrecision <= 10 ** 6);
        require(priceStandardDeviationsPrecision <= 10 ** 6);

        setWormhole(wormhole);
        setTokenBridge(tokenBridge);
        setPyth(pythAddress);
        setOracleMode(oracleMode);
        setConsistencyLevel(consistencyLevel);
        setInterestAccrualIndexPrecision(interestAccrualIndexPrecision);
        setCollateralizationRatioPrecision(collateralizationRatioPrecision);
        setMaxLiquidationBonus(maxLiquidationBonus); // use the precision of the collateralization ratio
        setMaxLiquidationPortion(maxLiquidationPortion);
        setMaxLiquidationPortionPrecision(maxLiquidationPortionPrecision);
        setMockPyth(60 * (10 ** 18), 0);
        setPriceStandardDeviations(priceStandardDeviations);
        setPriceStandardDeviationsPrecision(priceStandardDeviationsPrecision);
    }

    /**
     * @notice Registers asset on the hub. Only registered assets are allowed to be stored in the protocol.
     *
     * @param assetAddress: The address to be checked
     * @param collateralizationRatioDeposit: collateralizationRatioDeposit = crd * collateralizationRatioPrecision,
     * where crd is such that when we calculate 'fair prices' to see if a vault, after an action, would have positive value,
     * for purposes of allowing withdraws, borrows, or liquidations, we multiply any deposited amount of this asset by crd.
     * @param collateralizationRatioBorrow: collateralizationRatioBorrow = crb * collateralizationRatioPrecision,
     * where crb is such that when we calculate 'fair prices' to see if a vault, after an action, would have positive value,
     * for purposes of allowing withdraws, borrows, or liquidations, we multiply any borrowed amount of this asset by crb.
     * One way to think about crb is that for every '$1 worth' of effective deposits we allow $c worth of this asset borrowed
     * @param ratePrecision: A precision number that allows us to represent noninteger rate intercept value ri and rate coefficient value rca as integers.
     * @param kinks: x values of points on the piecewise linear curve, using ratePrecision for decimal expression
     * @param rates: y values of points on the piecewise linear curve, using ratePrecision for decimal expression;
     * @param reserveFactor: reserveFactor = rf * reservePrecision, The portion of the paid interest by borrowers that is diverted to the protocol for rainy day,
     * the remainder is distributed among lenders of the asset
     * @param reservePrecision: A precision number that allows us to represent our noninteger reserve factor rf as an integer (specifically reserveFactor = rf * reservePrecision)
     * @param pythId: Id of the relevant oracle price feed (USD <-> asset)
     */
    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatioDeposit,
        uint256 collateralizationRatioBorrow,
        uint64 ratePrecision,
        uint256[] memory kinks,
        uint256[] memory rates,
        uint256 reserveFactor,
        uint256 reservePrecision,
        bytes32 pythId
    ) public onlyOwner {
        AssetInfo memory registeredInfo = getAssetInfo(assetAddress);
        require(!registeredInfo.exists, "Asset already registered");

        allowAsset(assetAddress);

        PiecewiseInterestRateModel memory interestRateModel = PiecewiseInterestRateModel({
            ratePrecision: ratePrecision,
            kinks: kinks,
            rates: rates,
            reserveFactor: reserveFactor,
            reservePrecision: reservePrecision
        });

        (, bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        if (decimals > 18) {
            decimals = 18;
        }
        require(ratePrecision <= 10 ** 6);
        require(reservePrecision <= 10 ** 6);

        AssetInfo memory info = AssetInfo({
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            pythId: pythId,
            decimals: decimals,
            interestRateModel: interestRateModel,
            exists: true
        });

        registerAssetInfo(assetAddress, info);

        setLastActivityBlockTimestamp(assetAddress, block.timestamp);
    }

    /**
     * @notice Registers a spoke contract. Only wormhole messages from registered spoke contracts are allowed.
     *
     * @param chainId - The chain id which the spoke is deployed on
     * @param spokeContractAddress - The address of the spoke contract on its chain
     */
    function registerSpoke(uint16 chainId, address spokeContractAddress) public onlyOwner {
        registerSpokeContract(chainId, spokeContractAddress);
    }

    /**
     * @notice Completes a deposit that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with a TokenBridge message as the payload
     * The TokenBridge message is used to complete a TokenBridge transfer of tokens to the Hub,
     * and contains a payload of the deposit information
     */
    function completeDeposit(bytes memory encodedMessage) public {
        completeAction(encodedMessage, true);
    }

    /**
     * @notice Completes a withdraw that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with withdraw information as the payload
     */
    function completeWithdraw(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    /**
     * @notice Completes a borrow that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with borrow information as the payload
     */
    function completeBorrow(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    /**
     * @notice Completes a repay that was initiated on a spoke
     * @param encodedMessage: encoded Wormhole message with a TokenBridge message as the payload
     * The TokenBridge message is used to complete a TokenBridge transfer of tokens to the Hub,
     * and contains a payload of the repay information
     */
    function completeRepay(bytes memory encodedMessage) public {
        completeAction(encodedMessage, true);
    }

    /**
     * @notice Completes an action (deposit, borrow, withdraw, or repay) that was initiated on a spoke
     *
     * @param encodedMessage - Encoded wormhole message with either a TokenBridge payload with tokens as well as deposit/repay info, or a regular wormhole payload with withdraw/borrow info
     * @param isTokenBridgePayload - Whether or not the wormhole payload is a TokenBridge message (for Deposit or Repay) or a normal message (for Borrow or Withdraw)
     */
    function completeAction(bytes memory encodedMessage, bool isTokenBridgePayload)
        internal
        returns (bool completed, uint64 sequence)
    {
        bytes memory encodedActionPayload;
        IWormhole.VM memory parsed = getWormholeParsed(encodedMessage);

        if (isTokenBridgePayload) {
            encodedActionPayload = extractPayloadFromTransferPayload(getTransferPayload(encodedMessage));
        } else {
            verifySenderIsSpoke(parsed.emitterChainId, address(uint160(uint256(parsed.emitterAddress))));
            encodedActionPayload = parsed.payload;
        }

        ActionPayload memory params = decodeActionPayload(encodedActionPayload);
        Action action = Action(params.action);

        checkValidAddress(params.assetAddress);
        completed = true;
        bool transferTokensToSender = false;

        updateAccrualIndices(params.assetAddress);

        if (action == Action.Withdraw) {
            checkAllowedToWithdraw(params.sender, params.assetAddress, params.assetAmount);
            transferTokensToSender = true;
        } else if (action == Action.Borrow) {
            checkAllowedToBorrow(params.sender, params.assetAddress, params.assetAmount);
            transferTokensToSender = true;
        } else if (action == Action.Repay) {
            completed = allowedToRepay(params.sender, params.assetAddress, params.assetAmount);
            if (!completed) {
                transferTokensToSender = true;
            }
        }

        if (completed) {
            logActionOnHub(action, params.sender, params.assetAddress, params.assetAmount);
        }

        if (transferTokensToSender) {
            sequence = transferTokens(params.sender, params.assetAddress, params.assetAmount, parsed.emitterChainId);
        }
    }

    /**
     * @notice Liquidates a vault. The sender of this transaction pays, for each i, assetRepayAmount[i] of the asset assetRepayAddresses[i]
     * and receives, for each i, assetReceiptAmount[i] of the asset at assetReceiptAddresses[i].
     * A check is made to see if this liquidation attempt should be allowed
     *
     * @param vault - the address of the vault
     * @param assetRepayAddresses - An array of the addresses of the assets being paid by the liquidator
     * @param assetRepayAmounts - An array of the amounts of the assets being paid by the liquidator
     * @param assetReceiptAddresses - An array of the addresses of the assets being received by the liquidator
     * @param assetReceiptAmounts - An array of the amounts of the assets being received by the liquidator
     */
    function liquidation(
        address vault,
        address[] memory assetRepayAddresses,
        uint256[] memory assetRepayAmounts,
        address[] memory assetReceiptAddresses,
        uint256[] memory assetReceiptAmounts
    ) public {
        // check if inputs are valid
        checkLiquidationInputsValid(assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // check if intended liquidation is valid
        checkAllowedToLiquidate(
            vault, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );

        // for repay assets update amounts for vault and global
        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            logActionOnHub(Action.Repay, vault, assetRepayAddresses[i], assetRepayAmounts[i]);
        }

        // for received assets update amounts for vault and global
        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            logActionOnHub(Action.Withdraw, vault, assetReceiptAddresses[i], assetReceiptAmounts[i]);
        }

        // send repay tokens from liquidator to contract
        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(assetRepayAddresses[i]), msg.sender, address(this), assetRepayAmounts[i]);
        }
        // send receive tokens from contract to liquidator
        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            SafeERC20.safeTransfer(IERC20(assetReceiptAddresses[i]), msg.sender, assetReceiptAmounts[i]);
        }
    }

    /**
     * @notice Updates the vault's state to log either a deposit, borrow, withdraw, or repay
     *
     * @param action - the action (either Deposit, Borrow, Withdraw, or Repay)
     * @param vault - the address of the vault
     * @param assetAddress - the address of the relevant asset being logged
     * @param amount - the amount of the asset assetAddress being logged
     */
    function logActionOnHub(Action action, address vault, address assetAddress, uint256 amount)
        internal
    {

        VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        if (action == Action.Deposit) {
            uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited, Round.DOWN);
            vaultAmounts.deposited += normalizedDeposit;
            globalAmounts.deposited += normalizedDeposit;
        } else if (action == Action.Withdraw) {
            uint256 normalizedWithdraw = normalizeAmount(amount, indices.deposited, Round.UP);
            vaultAmounts.deposited -= normalizedWithdraw;
            globalAmounts.deposited -= normalizedWithdraw;
        } else if (action == Action.Borrow) {
            uint256 normalizedBorrow = normalizeAmount(amount, indices.borrowed, Round.UP);
            vaultAmounts.borrowed += normalizedBorrow;
            globalAmounts.borrowed += normalizedBorrow;
        } else if (action == Action.Repay) {
            uint256 normalizedRepay = normalizeAmount(amount, indices.borrowed, Round.DOWN);
            if(normalizedRepay > vaultAmounts.borrowed) {
                normalizedRepay = vaultAmounts.borrowed;
            }
            vaultAmounts.borrowed -= normalizedRepay;
            globalAmounts.borrowed -= normalizedRepay;
        }

        setVaultAmounts(vault, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }
}
