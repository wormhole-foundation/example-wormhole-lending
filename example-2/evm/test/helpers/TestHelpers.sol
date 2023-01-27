// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestSetters} from "./TestSetters.sol";
import {TestGetters} from "./TestGetters.sol";
import {TestUtilities} from "./TestUtilities.sol";

import "../../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

contract TestHelpers is TestStructs, TestState, TestGetters, TestSetters, TestUtilities {
    
    using BytesLib for bytes;


    function testSetUp(Vm vm) internal {

        // this will be used to sign wormhole messages
        uint256 guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS_MUMBAI"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        IWormhole wormholeContract = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormholeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_MUMBAI")), "wrong chainId");
        require(wormholeContract.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE_MUMBAI"), "wrong messageFee");
        require(
            wormholeContract.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX_MUMBAI")),
            "wrong guardian set index"
        );

        // set up Token Bridge
        ITokenBridge tokenBridgeContract = ITokenBridge(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_MUMBAI"));

        // verify Token Bridge state from fork
        require(tokenBridgeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_MUMBAI")), "wrong chainId");
        

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        uint256 interestAccrualIndexPrecision = 10 ** 6;
        uint256 collateralizationRatioPrecision = 10 ** 6;
        uint256 maxLiquidationBonus = 125 * 10**4;
        uint256 maxLiquidationPortion = 50;
        uint256 maxLiquidationPortionPrecision = 10 ** 2;
        uint8 oracleMode = 1;
        uint64 priceStandardDeviations = 424;
        uint64 priceStandardDeviationsPrecision = 10 ** 2;
        address pythAddress = vm.envAddress("TESTING_PYTH_ADDRESS_MUMBAI");

        Hub hub = new Hub(
            address(wormholeContract), 
            address(tokenBridgeContract), 
            wormholeFinality, 
            pythAddress, 
            oracleMode,
            priceStandardDeviations,
            priceStandardDeviationsPrecision, 
            maxLiquidationBonus, 
            maxLiquidationPortion, 
            maxLiquidationPortionPrecision,
            interestAccrualIndexPrecision, 
            collateralizationRatioPrecision
        );

        setOracleMode(oracleMode);

        setHubData(HubData({
            guardianSigner: guardianSigner,
            wormholeSimulator: wormholeSimulator,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            hub: hub,
            hubChainId: wormholeContract.chainId()
        }));

        setVm(vm);

        setPublishTime(1);
        
        registerChainOnHub(uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_MUMBAI")), bytes32(uint256(uint160(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_MUMBAI")))));

    }

    function doRegisterSpoke(uint256 index) internal returns (Spoke) {

        SpokeData memory spokeData = getSpokeData(index);
        // register asset
        getHub().registerSpoke(
            spokeData.foreignChainId, address(spokeData.spoke)
        );

        return spokeData.spoke;
    }

    function doRegisterAsset(Asset memory asset) internal {
        Vm vm = getVm();
        
        uint256 reservePrecision = 1 * 10**6;
        
        // register asset
        vm.recordLogs();
        getHub().registerAsset(
            asset.assetAddress, 
            asset.collateralizationRatioDeposit, 
            asset.collateralizationRatioBorrow,
            asset.ratePrecision,
            asset.kinks,
            asset.rates,
            asset.reserveFactor, 
            reservePrecision, 
            asset.pythId
        );
        
        AssetInfo memory info = getHub().getAssetInfo(asset.assetAddress);

        bool kinksMatch = true;
        bool ratesMatch = true;

        require(info.interestRateModel.kinks.length == asset.kinks.length, "lengths of kinks arrays don't match");
        require(info.interestRateModel.rates.length == asset.rates.length, "lengths of rates arrays don't match");

        for(uint i=0; i < asset.kinks.length; i++) {
            if (info.interestRateModel.kinks[i] != asset.kinks[i]) {
                kinksMatch = false;
            }
        }

        for(uint i=0; i < asset.rates.length; i++) {
            if (info.interestRateModel.rates[i] != asset.rates[i]) {
                ratesMatch = false;
            }
        }

        require(
            (info.collateralizationRatioDeposit == asset.collateralizationRatioDeposit) && (info.collateralizationRatioBorrow == asset.collateralizationRatioBorrow) && (info.decimals == asset.decimals) && (info.pythId == asset.pythId) && (info.exists) && (info.interestRateModel.ratePrecision == asset.ratePrecision) && (kinksMatch) && (ratesMatch) && (info.interestRateModel.reserveFactor == asset.reserveFactor) && (info.interestRateModel.reservePrecision == reservePrecision), 
            "didn't register properly" 
        );
    }
   
    function doAction(ActionParameters memory params) internal {
        
        Action action = Action(params.action);
        bool isNative = params.action == Action.DepositNative || params.action == Action.RepayNative;
        Spoke spoke = getSpoke(params.spokeIndex);
        address vault = address(this);
        if(params.prank) {
            vault = params.prankAddress;
        }
        if(getDebug()) {
            console.log("-[Vault %s]--------------", vault);
        }
        Vm vm = getVm();
        ActionStateData memory beforeData = getActionStateData(vault, params.assetAddress, isNative);
        if(action == Action.Deposit || action == Action.Repay) {
            if(params.prank) {
                vm.prank(vault);
            }
            IERC20(params.assetAddress).approve(address(spoke), params.assetAmount);
        }
        if(params.prank) {
            vm.prank(vault);
        }

        vm.recordLogs();
        if(action == Action.Deposit) {
            if(getDebug()) {
                console.log("Depositing %s of asset %s", params.assetAmount, getAssetIndex(params.assetAddress));
            }
            spoke.depositCollateral(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Repay) {
            if(getDebug()) {
                console.log("Repaying %s of asset %s", params.assetAmount, getAssetIndex(params.assetAddress));
            }
            spoke.repay(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Borrow) {
            if(getDebug()) {
                console.log("Borrowing %s of asset %s", params.assetAmount, getAssetIndex(params.assetAddress));
            }
            spoke.borrow(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Withdraw) {
            if(getDebug()) {
                console.log("Withdrawing %s of asset %s", params.assetAmount, getAssetIndex(params.assetAddress));
            }
            spoke.withdrawCollateral(params.assetAddress, params.assetAmount);
        } else if(action == Action.DepositNative) {
            if(getDebug()) {
                console.log("Depositing %s of native token", params.assetAmount);
            }
            spoke.depositCollateralNative{value: params.assetAmount}();
        }
        else if(action == Action.RepayNative) {
            if(getDebug()) {
                console.log("Repaying %s of native token", params.assetAmount);
            }
            spoke.repayNative{value: params.assetAmount}();
        }
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(params.spokeIndex, entries[entries.length - 1]);

        if(params.expectRevert) {
            vm.expectRevert(bytes(params.revertString));
        }
        if(action == Action.Deposit || action == Action.DepositNative) {
            getHub().completeDeposit(encodedMessage);
        }
        else if(action == Action.Repay || action == Action.RepayNative) {
            getHub().completeRepay(encodedMessage);
        }
        else if(action == Action.Borrow) {
            getHub().completeBorrow(encodedMessage);
        }
        else if(action == Action.Withdraw) {
            getHub().completeWithdraw(encodedMessage);
        } 
        if(params.expectRevert) {
            if(getDebug()) {
            console.log("should revert");
            console.log("----------------------------------------");
            console.log("");
            }
            return;
        }

        if(action == Action.Borrow || action == Action.Withdraw || params.paymentReversion) {
            entries = vm.getRecordedLogs();
            encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);
            spoke.tokenBridge().completeTransfer(encodedMessage);
        }

        ActionStateData memory afterData = getActionStateData(vault, params.assetAddress, isNative);

        uint256 amount = params.assetAmount;
        if(isNative) amount = amount - getHubData().wormholeContract.messageFee();
        requireActionDataValid(action, params.assetAddress, amount, beforeData, afterData, params.paymentReversion);

        if(getDebug()) {
            console.log("----------------------------------------");
            console.log("");
        }
    }

    
    function doDeposit(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Deposit,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doDeposit(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doAction(ActionParameters({
            action: Action.Deposit,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
    function doDepositRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Deposit,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doDepositNative(uint256 spokeIndex, uint256 amount) internal {
        doAction(ActionParameters({
            action: Action.DepositNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doDepositNative(uint256 spokeIndex, uint256 amount, address vault) internal {
        doAction(ActionParameters({
            action: Action.DepositNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
    function doDepositNativeRevert(uint256 spokeIndex, uint256 amount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.DepositNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address prankAddress) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: prankAddress
        }));
    }
    function doRepayRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    
    function doRepayRevertPayment(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: true,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepayRevertPayment(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: true,
            prank: true,
            prankAddress: vault
        }));
    }
    
    function doRepayNative(uint256 spokeIndex, uint256 amount) internal {
        doAction(ActionParameters({
            action: Action.RepayNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepayNative(uint256 spokeIndex, uint256 amount, address vault) internal {
        doAction(ActionParameters({
            action: Action.RepayNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
    function doRepayNativeRevertPayment(uint256 spokeIndex, uint256 amount) internal {
        doAction(ActionParameters({
            action: Action.RepayNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: true,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepayNativeRevertPayment(uint256 spokeIndex, uint256 amount, address vault) internal {
        doAction(ActionParameters({
            action: Action.RepayNative,
            spokeIndex: spokeIndex,
            assetAddress: address(getHubData().tokenBridgeContract.WETH()),
            assetAmount: amount,
            expectRevert: false,
            revertString: "",
            paymentReversion: true,
            prank: true,
            prankAddress: vault
        }));
    }
    function doBorrow(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Borrow,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doBorrow(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doAction(ActionParameters({
            action: Action.Borrow,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
    function doBorrowRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Borrow,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }

    function doBorrowRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString, address prankAddress) internal {
        doAction(ActionParameters({
            action: Action.Borrow,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: true,
            prankAddress: prankAddress
        }));
    }
    
    function doWithdraw(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Withdraw,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doWithdraw(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doAction(ActionParameters({
            action: Action.Withdraw,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
    function doWithdrawRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Withdraw,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doWithdrawRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Withdraw,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            paymentReversion: false,
            prank: true,
            prankAddress: vault
        }));
    }
 
    function setPrice(Asset memory asset, int64 price) internal {
       setPrice(asset, price, 0, 0, 100, 100);
    }

    function setPrice(Asset memory asset, int64 price, uint64 conf, int32 expo, int64 emaPrice, uint64 emaConf) internal {
        
        uint64 publishTime = getPublishTime();
        publishTime += 1;
        setPublishTime(publishTime);
        
        if(getOracleMode() == 1){
            getHub().setMockPythFeed(asset.pythId, price, conf, expo, emaPrice, emaConf, publishTime);
        }
        else if(getOracleMode() == 2){
            getHub().setOraclePrice(asset.pythId, Price({price: price, conf: conf, expo: expo, publishTime: publishTime}));
        }
    }

    function doLiquidate(address vaultToLiquidate, address[] memory repayAddresses, uint256[] memory repayAmounts, address[] memory receiptAddresses, uint256[] memory receiptAmounts) internal {
        doLiquidate(vaultToLiquidate, repayAddresses, repayAmounts, receiptAddresses, receiptAmounts, false, "");
    }

    function doLiquidate(address vaultToLiquidate, address[] memory repayAddresses, uint256[] memory repayAmounts, address[] memory receiptAddresses, uint256[] memory receiptAmounts, string memory revertString) internal {
        doLiquidate(vaultToLiquidate, repayAddresses, repayAmounts, receiptAddresses, receiptAmounts, true, revertString);
    }

    function doLiquidate(address vaultToLiquidate, address[] memory repayAddresses, uint256[] memory repayAmounts, address[] memory receiptAddresses, uint256[] memory receiptAmounts, bool expectRevert, string memory revertString) internal {
        
        uint256 repayLength = repayAddresses.length;
        uint256 receiptLength = repayAddresses.length;

        LiquidationDataArrays memory lda;

        lda.userBalancePreRepay = new uint256[](repayLength);
        lda.hubBalancePreRepay  = new uint256[](repayLength);
        lda.userBalancePostRepay  = new uint256[](repayLength);
        lda.hubBalancePostRepay  = new uint256[](repayLength);

        lda.userBalancePreReceipt = new uint256[](receiptLength);
        lda.hubBalancePreReceipt  = new uint256[](receiptLength);
        lda.userBalancePostReceipt = new uint256[](receiptLength);
        lda.hubBalancePostReceipt  = new uint256[](receiptLength);

        lda.vaultToLiquidateAmountRepayPre = new uint256[](repayLength);
        lda.vaultToLiquidateAmountReceiptPre = new uint256[](receiptLength);
        lda.vaultToLiquidateAmountRepayPost = new uint256[](repayLength);
        lda.vaultToLiquidateAmountReceiptPost = new uint256[](receiptLength);

        lda.globalAmountRepayPre = new uint256[](repayLength);
        lda.globalAmountReceiptPre = new uint256[](receiptLength);
        lda.globalAmountRepayPost = new uint256[](repayLength);
        lda.globalAmountReceiptPost = new uint256[](receiptLength);

        for(uint256 i=0; i<repayLength; i++) {
            IERC20(repayAddresses[i]).approve(address(getHub()), repayAmounts[i]);
            lda.userBalancePreRepay[i] = IERC20(repayAddresses[i]).balanceOf(address(this));
            lda.hubBalancePreRepay[i] = IERC20(repayAddresses[i]).balanceOf(address(getHub()));

            lda.vaultToLiquidateAmountRepayPre[i] = getHub().getUserBalance(vaultToLiquidate, repayAddresses[i]).borrowed;
            lda.globalAmountRepayPre[i] = getHub().getGlobalBalance(repayAddresses[i]).borrowed;
        }

        for(uint256 i=0; i<receiptLength; i++) {
            lda.userBalancePreReceipt[i] = IERC20(receiptAddresses[i]).balanceOf(address(this));
            lda.hubBalancePreReceipt[i] = IERC20(receiptAddresses[i]).balanceOf(address(getHub()));

            lda.vaultToLiquidateAmountReceiptPre[i] = getHub().getUserBalance(vaultToLiquidate, receiptAddresses[i]).deposited;
            lda.globalAmountReceiptPre[i] = getHub().getGlobalBalance(receiptAddresses[i]).deposited;
        }

        if(expectRevert) {
            getVm().expectRevert(bytes(revertString));
        }
        getHub().liquidation(vaultToLiquidate, repayAddresses, repayAmounts, receiptAddresses, receiptAmounts);

        if(expectRevert) {
            return;
        }
    
        for(uint256 i=0; i<repayLength; i++) {
            lda.userBalancePostRepay[i] = IERC20(repayAddresses[i]).balanceOf(address(this));
            lda.hubBalancePostRepay[i] = IERC20(repayAddresses[i]).balanceOf(address(getHub()));

            lda.vaultToLiquidateAmountRepayPost[i] = getHub().getUserBalance(vaultToLiquidate, repayAddresses[i]).borrowed;
            lda.globalAmountRepayPost[i] = getHub().getGlobalBalance(repayAddresses[i]).borrowed;

            require(lda.userBalancePreRepay[i] == lda.userBalancePostRepay[i] + repayAmounts[i], "User didn't pay tokens for the repay");
            require(lda.hubBalancePreRepay[i] + repayAmounts[i] == lda.hubBalancePostRepay[i], "Hub didn't receive tokens for the repay");
            require(lda.vaultToLiquidateAmountRepayPost[i] + repayAmounts[i]== lda.vaultToLiquidateAmountRepayPre[i], "Vault repay amount not tracked properly");
            require(lda.globalAmountRepayPost[i] + repayAmounts[i] == lda.globalAmountRepayPre[i], "Global repay amount not tracked properly");
        }
        for(uint256 i=0; i<receiptLength; i++) {
            lda.userBalancePostReceipt[i] = IERC20(receiptAddresses[i]).balanceOf(address(this));
            lda.hubBalancePostReceipt[i] = IERC20(receiptAddresses[i]).balanceOf(address(getHub()));

            lda.vaultToLiquidateAmountReceiptPost[i] = getHub().getUserBalance(vaultToLiquidate, receiptAddresses[i]).deposited;
            lda.globalAmountReceiptPost[i] = getHub().getGlobalBalance(receiptAddresses[i]).deposited;

            require(lda.userBalancePreReceipt[i] + receiptAmounts[i] == lda.userBalancePostReceipt[i], "User didn't receive tokens for the receipt");
            require(lda.hubBalancePreReceipt[i] == lda.hubBalancePostReceipt[i] + receiptAmounts[i], "Hub didn't pay tokens for the receipt");
            require(lda.vaultToLiquidateAmountReceiptPost[i] + receiptAmounts[i] == lda.vaultToLiquidateAmountReceiptPre[i], "Vault receipt amount not tracked properly");
            require(lda.globalAmountReceiptPost[i] + receiptAmounts[i] == lda.globalAmountReceiptPre[i] , "Global receipt amount not tracked properly");
        }

    }

}
