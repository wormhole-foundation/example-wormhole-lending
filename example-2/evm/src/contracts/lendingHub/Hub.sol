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
    * address wormhole: Address of the Wormhole contract on the Hub chain
    * address tokenBridge: Address of the TokenBridge contract on the Hub chain
    * uint8 consistencyLevel: Desired level of finality the Wormhole guardians will reach before signing the messages
    * Note: consistencyLevel = 200 will result in an instant message, while all other values will wait for finality
    * Recommended finality levels can be found here: https://book.wormhole.com/reference/contracts.html
    * 
    * address pythAddress: Address of the Pyth oracle on the Hub chain
    * uint8 oracleMode: Variable that should be 0 and exists only for testing purposes. 
    * If oracleMode = 0, Hub uses Pyth; if 1, Hub uses a mock Pyth for testing, and if 2, Hub uses a dummy oracle that can be manually set
    * uint64 priceStandardDeviations: priceStandardDeviations = (psd * priceStandardDeviationsPrecision), where psd is the number of standard deviations that we use for our price intervals in calculations relating to allowing withdraws, borrows, or liquidations
    * uint64 priceStandardDeviationsPrecision: A precision number that allows us to represent our desired noninteger price standard deviation as an integer (specifically, psd = priceStandardDeviations/priceStandardDeviationsPrecision)
    *
    * uint256 maxLiquidationBonus: maxLiquidationBonus = (mlb * collateralizationRatioPrecision), where mlb is the multiplier such that if the fair value of a liquidator's repayed assets is v, the assets they receive can have a maximum of mlb*v in fair value. Fair value is computed using Pyth prices.
    * uint256 maxLiquidationPortion: maxLiquidationPortion = (mlp * maxLiquidationPortionPrecision), where mlp is the maximum fraction of the borrowed value vault that a liquidator can liquidate at once. 
    * uint256 maxLiquidationPortionPrecision: A precision number that allows us to represent our desired noninteger max liquidation portion mlp as an integer (specifically, mlp = maxLiquidationPortion/maxLiquidationPortionPrecision)
    *
    * uint256 interestAccrualIndexPrecision: A precision number that allows us to represent our noninteger interest accrual indices as integers; we store each index as its true value multiplied by interestAccrualIndexPrecision
    * uint256 collateralizationRatioPrecision: A precision number that allows us to represent our noninteger collateralization ratios as integers; we store each ratio as its true value multiplied by collateralizationRatioPrecision
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
        setPriceStandardDeviations(priceStandardDeviations, priceStandardDeviationsPrecision);
    }

    /**
     * Registers asset on the hub. Only registered assets are allowed to be stored in the protocol.
     *
     * @param assetAddress - The address to be checked
     * @param collateralizationRatioDeposit - The constant c multiplied by collateralizationRatioPrecision,
     * where c is such that we account $1 worth of effective deposits per actual $c worth of this asset deposited
     * @param collateralizationRatioBorrow - The constant c multiplied by collateralizationRatioPrecision,
     * where c is such that for every $1 worth of effective deposits we allow $c worth of this asset borrowed
     * (according to Pyth prices)
     * @param reserveFactor - The portion of the paid interest by borrowers that is diverted to the protocol for rainy day,
     * the remainder is distributed among lenders of the asset
     * @param pythId - Id of the relevant oracle price feed (USD <-> asset)  
     */
    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatioDeposit,
        uint256 collateralizationRatioBorrow,
        uint64 ratePrecision,
        uint64 rateIntercept,
        uint64 rateCoefficientA,
        uint256 reserveFactor,
        uint256 reservePrecision,
        bytes32 pythId
    ) public onlyOwner {

        AssetInfo memory registeredInfo = getAssetInfo(assetAddress);
        require(!registeredInfo.exists, "Asset already registered");

        allowAsset(assetAddress);

        InterestRateModel memory interestRateModel = InterestRateModel({
            ratePrecision: ratePrecision,
            rateIntercept: rateIntercept,
            rateCoefficientA: rateCoefficientA,
            reserveFactor: reserveFactor,
            reservePrecision: reservePrecision
        });

        (,bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        AssetInfo memory info = AssetInfo({
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            pythId: pythId,
            decimals: decimals,
            interestRateModel: interestRateModel,
            exists: true
        });

        registerAssetInfo(assetAddress, info);
    }

    /**
     * Registers a spoke contract. Only wormhole messages from registered spoke contracts are allowed.
     *
     * @param chainId - The chain id which the spoke is deployed on
     * @param spokeContractAddress - The address of the spoke contract on its chain
     */
    function registerSpoke(uint16 chainId, address spokeContractAddress) public onlyOwner {
        registerSpokeContract(chainId, spokeContractAddress);
    }

    function completeDeposit(bytes memory encodedMessage) public {
        completeAction(encodedMessage, true);
    }

    function completeWithdraw(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    function completeBorrow(bytes memory encodedMessage) public {
        completeAction(encodedMessage, false);
    }

    function completeRepay(bytes memory encodedMessage) public {
        completeAction(encodedMessage, true);
    }

     /**
     * Completes an action (deposit, borrow, withdraw, or repay) that was initiated on a spoke
     *
     * @param encodedMessage - Encoded wormhole VAA with either a TokenBridge payload with tokens as well as deposit/repay info, or a regular wormhole payload with withdraw/borrow info
     * @param isTokenBridgePayload - Whether or not the wormhole payload is a TokenBridge message (for Deposit or Repay) or a normal message (for Borrow or Withdraw)
     */
    function completeAction(bytes memory encodedMessage, bool isTokenBridgePayload) internal returns (bool completed, uint64 sequence) {
        
        bytes memory encodedActionPayload;
        IWormhole.VM memory parsed = getWormholeParsed(encodedMessage);
        
        if(isTokenBridgePayload) {
            encodedActionPayload = extractPayloadFromTransferPayload(getTransferPayload(encodedMessage));
        } else {
            verifySenderIsSpoke(parsed.emitterChainId, address(uint160(uint256(parsed.emitterAddress)))); 
            encodedActionPayload = parsed.payload;
        }

        ActionPayload memory params = decodeActionPayload(encodedActionPayload);
        Action action = Action(params.action);

        checkValidAddress(params.assetAddress);
        bool returnTokensForInvalidRepay = false;

        if(action == Action.Withdraw) {
            checkAllowedToWithdraw(params.sender, params.assetAddress, params.assetAmount);
        } else if(action == Action.Borrow) {
            checkAllowedToBorrow(params.sender, params.assetAddress, params.assetAmount);
        } else if(action == Action.Repay) {
            returnTokensForInvalidRepay = !allowedToRepay(params.sender, params.assetAddress, params.assetAmount);
        } 

        uint256 actualAmount = params.assetAmount;

        if(!returnTokensForInvalidRepay) {
            actualAmount = logActionOnHub(action, params.sender, params.assetAddress, params.assetAmount);
        }

        if(action == Action.Withdraw || action == Action.Borrow || returnTokensForInvalidRepay) {
            sequence = transferTokens(params.sender, params.assetAddress, actualAmount, parsed.emitterChainId);
        }
        
        completed = !returnTokensForInvalidRepay;
    } 

    /**
     * Liquidates a vault. The sender of this transaction pays, for each i, assetRepayAmount[i] of the asset assetRepayAddresses[i]
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
        checkAllowedToLiquidate(vault, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // for repay assets update amounts for vault and global
        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            logActionOnHub(Action.Repay, vault, assetRepayAddresses[i], assetRepayAmounts[i]);
        }

        uint256[] memory assetReceiptActualAmounts = new uint256[](assetReceiptAmounts.length);

        // for received assets update amounts for vault and global
        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            assetReceiptActualAmounts[i] = logActionOnHub(Action.Withdraw, vault, assetReceiptAddresses[i], assetReceiptAmounts[i]);
        }

        // send repay tokens from liquidator to contract
        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(assetRepayAddresses[i]), msg.sender, address(this), assetRepayAmounts[i]);
        }
        // send receive tokens from contract to liquidator
        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            SafeERC20.safeTransfer(IERC20(assetReceiptAddresses[i]), msg.sender, assetReceiptActualAmounts[i]);
        }
    }

    /**
     * Updates the vault's state to log either a deposit, borrow, withdraw, or repay
     *
     * @param action - the action (either Deposit, Borrow, Withdraw, or Repay)
     * @param vault - the address of the vault
     * @param assetAddress - the address of the relevant asset being logged
     * @param amount - the amount of the asset assetAddress being logged
     */
    function logActionOnHub(Action action, address vault, address assetAddress, uint256 amount) internal returns (uint256 actualAmount) {
        updateAccrualIndices(assetAddress);

        VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        if(action == Action.Deposit) {
            uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited);
            vaultAmounts.deposited += normalizedDeposit;
            globalAmounts.deposited += normalizedDeposit;
            actualAmount = denormalizeAmount(normalizedDeposit, indices.deposited);
        } else if(action == Action.Withdraw) {
            uint256 normalizedWithdraw = normalizeAmount(amount, indices.deposited);
            vaultAmounts.deposited -= normalizedWithdraw;
            globalAmounts.deposited -= normalizedWithdraw;
            actualAmount = denormalizeAmount(normalizedWithdraw, indices.deposited);
        } else if(action == Action.Borrow) {
            uint256 normalizedBorrow = normalizeAmount(amount, indices.borrowed);
            vaultAmounts.borrowed += normalizedBorrow;
            globalAmounts.borrowed += normalizedBorrow;
            actualAmount = denormalizeAmount(normalizedBorrow, indices.borrowed);
        } else if(action == Action.Repay) {
            uint256 normalizedRepay = normalizeAmount(amount, indices.borrowed);
            vaultAmounts.borrowed -= normalizedRepay;
            globalAmounts.borrowed -= normalizedRepay;
            actualAmount = denormalizeAmount(normalizedRepay, indices.borrowed);
        }

        setVaultAmounts(vault, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

}
