// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

import "../../interfaces/IWormhole.sol";

import "forge-std/console.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";
import "./HubUtilities.sol"; 

contract Hub is HubStructs, HubMessages, HubGetters, HubSetters, HubUtilities {
    constructor(
        address wormhole_, 
        address tokenBridge_, 
        address pythAddress_,
        uint8 oracleMode_,
        uint8 consistencyLevel_, 
        uint256 interestAccrualIndexPrecision_, 
        uint256 collateralizationRatioPrecision_, 
        uint8 initialMaxDecimals_, 
        uint256 maxLiquidationBonus_, 
        uint256 maxLiquidationPortion, 
        uint256 maxLiquidationPortionPrecision
    ) {
        setOwner(_msgSender());
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
        setPyth(pythAddress_);
        setOracleMode(oracleMode_);
        setMaxDecimals(initialMaxDecimals_);
        setConsistencyLevel(consistencyLevel_);
        setInterestAccrualIndexPrecision(interestAccrualIndexPrecision_);
        setCollateralizationRatioPrecision(collateralizationRatioPrecision_);
        setMaxLiquidationBonus(maxLiquidationBonus_); // use the precision of the collateralization ratio
        setMaxLiquidationPortion(maxLiquidationPortion);
        setMaxLiquidationPortionPrecision(maxLiquidationPortionPrecision);

        uint validTimePeriod = 60 * (10**18);
        uint singleUpdateFeeInWei = 0;
        setMockPyth(validTimePeriod, singleUpdateFeeInWei);        
    }

    /**
    * Registers asset on the hub. Only registered assets are allowed to be stored in the protocol.
    *
    * @param assetAddress - The address to be checked
    * @param collateralizationRatioDeposit - The constant c divided by collateralizationRatioPrecision, 
    * where c is such that we account $1 worth of effective deposits per actual $c worth of this asset deposited
    * @param collateralizationRatioBorrow - The constant c divided by collateralizationRatioPrecision, 
    * where c is such that for every $1 worth of effective deposits we allow $c worth of this asset borrowed 
    * (according to Pyth prices) 
    * @param reserveFactor - The portion of the paid interest by borrowers that is diverted to the protocol for rainy day,
    * the remainder is distributed among lenders of the asset
    * @param pythId - Id of the relevant oracle price feed (USD <-> asset) TODO: Make this explanation more precise
    * @param decimals - Precision that the asset amount is stored in TODO: Make this explanation more precise
    * @return sequence The sequence number of the wormhole message documenting the registration of the asset
    */ 
    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatioDeposit,
        uint256 collateralizationRatioBorrow,
        uint256 reserveFactor,
        uint256 reservePrecision,
        bytes32 pythId,
        uint8 decimals
    ) public returns (uint64 sequence) {
        require(msg.sender == owner(), "invalid owner");

        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(!registered_info.exists, "Asset already registered");

        allowAsset(assetAddress);

        InterestRateModel memory interestRateModel = InterestRateModel({
            ratePrecision: 1 * 10**18,
            rateIntercept: 0,
            rateCoefficientA: 0,
            reserveFactor: reserveFactor,
            reservePrecision: reservePrecision
        });

        AssetInfo memory info = AssetInfo({
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            pythId: pythId,
            decimals: decimals,
            interestRateModel: interestRateModel,
            exists: true
        });

        registerAssetInfo(assetAddress, info);

        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 5,
            sender: address(this)
        });

        RegisterAssetPayload memory registerAssetPayload = RegisterAssetPayload({
            header: payloadHeader,
            assetAddress: assetAddress,
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            pythId: pythId,
            ratePrecision: interestRateModel.ratePrecision,
            rateIntercept: interestRateModel.rateIntercept,
            rateCoefficientA: interestRateModel.rateCoefficientA,
            reserveFactor: interestRateModel.reserveFactor,
            reservePrecision: interestRateModel.reservePrecision,
            decimals: decimals
        });

        // create WH message
        bytes memory serialized = encodeRegisterAssetPayload(registerAssetPayload);

        sequence = sendWormholeMessage(serialized);
    }

    /**
    * Registers a spoke contract. Only wormhole messages from registered spoke contracts are allowed.
    *
    * @param chainId - The chain id which the spoke is deployed on
    * @param spokeContractAddress - The address of the spoke contract on its chain 
    */ 
    function registerSpoke(uint16 chainId, address spokeContractAddress) public {
        require(msg.sender == owner(), "invalid owner");
        registerSpokeContract(chainId, spokeContractAddress);
    }

    /**
    * Completes a deposit that was initiated on a spoke
    *
    * @param encodedMessage - Encoded token bridge VAA (payload3) with the tokens deposited and deposit information
    */ 
    function completeDeposit(bytes memory encodedMessage) public { // calldata encodedMessage

        // encodedMessage is WH full msg, returns token bridge transfer msg

        bytes memory vmPayload = getTransferPayload(encodedMessage);

        bytes memory serialized = extractSerializedFromTransferWithPayload(vmPayload);

        DepositPayload memory params = decodeDepositPayload(serialized);

        deposit(params.header.sender, params.assetAddress, params.assetAmount);

    }

    /**
    * Completes a withdraw that was initiated on a spoke
    *
    * @param encodedMessage - Encoded VAA with the withdraw information
    */
    function completeWithdraw(bytes calldata encodedMessage) public {

        IWormhole.VM memory parsed = getWormholeParsed(encodedMessage);
        bytes memory serialized = parsed.payload;
        WithdrawPayload memory params = decodeWithdrawPayload(serialized);

        withdraw(params.header.sender, params.assetAddress, params.assetAmount, parsed.emitterChainId);
    }

    /**
    * Completes a borrow that was initiated on a spoke
    *
    * @param encodedMessage - Encoded VAA with the borrow information
    */
    function completeBorrow(bytes calldata encodedMessage) public {

        // encodedMessage is WH full msg, returns arbitrary bytes
        IWormhole.VM memory parsed = getWormholeParsed(encodedMessage);
        bytes memory serialized = parsed.payload;
        BorrowPayload memory params = decodeBorrowPayload(serialized);

        borrow(params.header.sender, params.assetAddress, params.assetAmount, parsed.emitterChainId);
    }

    /**
    * Completes a repay that was initiated on a spoke
    *
    * @param encodedMessage - Encoded token bridge VAA (payload3) with the repayed tokens and repay information
    */
    function completeRepay(bytes calldata encodedMessage) public {

        // encodedMessage is Token Bridge payload 3 full msg
        bytes memory vmPayload = getTransferPayload(encodedMessage);

        bytes memory serialized = extractSerializedFromTransferWithPayload(vmPayload);

        RepayPayload memory params = decodeRepayPayload(serialized);
        
        repay(params.header.sender, params.assetAddress, params.assetAmount);
    }

    /**
    * Updates vault amounts for a deposit from depositor of the asset at 'assetAddress' and amount 'amount'
    *
    * @param depositor - the address of the depositor
    * @param assetAddress - the address of the asset 
    * @param amount - the amount of the asset
    */
    function deposit(address depositor, address assetAddress, uint256 amount) internal {
        // TODO: What to do if this fails?
        
        checkValidAddress(assetAddress);

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        // calculate the normalized amount and store in the vault
        // update the global contract state with normalized amount
        VaultAmount memory vaultAmounts = getVaultAmounts(depositor, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited);

        vaultAmounts.deposited += normalizedDeposit;
        globalAmounts.deposited += normalizedDeposit;

        setVaultAmounts(depositor, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

    /**
    * Updates vault amounts for a withdraw from withdrawer of the asset at 'assetAddress' and amount 'amount'
    *
    * @param withdrawer - the address of the withdrawer
    * @param assetAddress - the address of the asset 
    * @param amount - the amount of the asset
    */
    function withdraw(address withdrawer, address assetAddress, uint256 amount, uint16 recipientChain) internal {
        checkValidAddress(assetAddress);

        // recheck if withdraw is valid given up to date prices? bc the prices can move in the time for VAA to come
        (bool check1, bool check2, bool check3) = allowedToWithdraw(withdrawer, assetAddress, amount);
        require(check1, "Not enough in vault");
        require(check2, "Not enough in global supply");
        require(check3, "Vault is undercollateralized if this withdraw goes through");

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

        transferTokens(withdrawer, assetAddress, amount, recipientChain);
    }

    /**
    * Updates vault amounts for a borrow from borrower of the asset at 'assetAddress' and amount 'amount'
    *
    * @param borrower - the address of the borrower
    * @param assetAddress - the address of the asset 
    * @param amount - the amount of the asset
    */
    function borrow(address borrower, address assetAddress, uint256 amount, uint16 recipientChain) internal {
        checkValidAddress(assetAddress);

        // recheck if borrow is valid given up to date prices? bc the prices can move in the time for VAA to come
        (bool check1, bool check2) = allowedToBorrow(borrower, assetAddress, amount);
        require(check1, "Not enough in global supply");
        require(check2, "Vault is undercollateralized if this borrow goes through");

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(borrower, assetAddress);
        vaultAmounts.borrowed += normalizedAmount;
   
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed += normalizedAmount;

        setVaultAmounts(borrower, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);

        // TODO: token transfers
        transferTokens(borrower, assetAddress, amount, recipientChain);
    }

    /**
    * Updates vault amounts for a repay from repayer of the asset at 'assetAddress' and amount 'amount'
    *
    * @param repayer - the address of the repayer
    * @param assetAddress - the address of the asset 
    * @param amount - the amount of the asset
    */
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

        setVaultAmounts(repayer, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
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
    function liquidation(address vault, address[] memory assetRepayAddresses, uint256[] memory assetRepayAmounts, address[] memory assetReceiptAddresses, uint256[] memory assetReceiptAmounts) public {
        // check if asset addresses all valid
        // TODO: eventually check all addresses in one function checkValidAddresses that checks for no duplicates also
        for(uint i=0; i<assetRepayAddresses.length; i++){
            checkValidAddress(assetRepayAddresses[i]);
        }
        for(uint i=0; i<assetReceiptAddresses.length; i++){
            checkValidAddress(assetReceiptAddresses[i]);
        }
        checkDuplicates(assetRepayAddresses);

        // update the interest accrual indices
        // TODO: Make more efficient
        address[] memory allowList = getAllowList();
        for(uint i=0; i<allowList.length; i++){
            updateAccrualIndices(allowList[i]);
        }

        // check if intended liquidation is valid
        require(allowedToLiquidate(vault, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts), "Liquidation attempt not allowed");

        // for repay assets update amounts for vault and global
        for(uint i=0; i<assetRepayAddresses.length; i++){
            address assetAddress = assetRepayAddresses[i];
            uint256 assetAmount = assetRepayAmounts[i];

            AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(assetAmount, indices.borrowed);
            // update state for vault
            VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
            // require that amount paid back <= amount borrowed
            uint256 denormalizedBorrowedAmount = denormalizeAmount(vaultAmounts.borrowed, indices.borrowed);
            require(denormalizedBorrowedAmount >= assetAmount, "cannot repay more than has been borrowed");
            vaultAmounts.borrowed -= normalizedAmount;
            // update global state
            VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
            globalAmounts.borrowed -= normalizedAmount;

            setVaultAmounts(vault, assetAddress, vaultAmounts);
            setGlobalAmounts(assetAddress, globalAmounts);
        }

        // for received assets update amounts for vault and global
        for (uint256 i=0; i<assetReceiptAddresses.length; i++) {
            address assetAddress = assetReceiptAddresses[i];
            uint256 assetAmount = assetReceiptAmounts[i];

            AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(assetAmount, indices.deposited);
            // update state for vault
            VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
            // require that amount received <= amount deposited
            uint256 denormalizedDepositedAmount = denormalizeAmount(vaultAmounts.deposited, indices.deposited);
            require(denormalizedDepositedAmount >= assetAmount, "cannot take out more collateral than vault has deposited");
            vaultAmounts.deposited -= normalizedAmount;
            // update global state
            VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
            globalAmounts.deposited -= normalizedAmount;

            setVaultAmounts(vault, assetAddress, vaultAmounts);
            setGlobalAmounts(assetAddress, globalAmounts);
        }

        // send repay tokens from liquidator to contract
        for(uint i=0; i<assetRepayAddresses.length; i++){
            address assetAddress = assetRepayAddresses[i];
            uint256 assetAmount = assetRepayAmounts[i];

            SafeERC20.safeIncreaseAllowance(
                IERC20(assetAddress), 
                msg.sender, 
                assetAmount
            );
            SafeERC20.safeTransferFrom(
                IERC20(assetAddress),
                msg.sender,
                address(this),
                assetAmount
            );
        }

        // send receive tokens from contract to liquidator
        for(uint i=0; i<assetReceiptAddresses.length; i++){
            address assetAddress = assetReceiptAddresses[i];
            uint256 assetAmount = assetReceiptAmounts[i];

            SafeERC20.safeTransfer(
                IERC20(assetAddress),
                msg.sender,
                assetAmount
            );
        }
    }
}
