// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../../src/contracts/lendingHub/HubMessages.sol";
import {HubUtilities} from "../../src/contracts/lendingHub/HubUtilities.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../../src/interfaces/ITokenImplementation.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestSetters} from "./TestSetters.sol";
import {TestGetters} from "./TestGetters.sol";
import {TestUtilities} from "./TestUtilities.sol";

import "../../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestHelpers is HubStructs, HubMessages, TestStructs, TestState, TestGetters, TestSetters, TestUtilities {
    
    using BytesLib for bytes;


    function testSetUp(Vm vm) internal {

        // this will be used to sign wormhole messages
        uint256 guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS_AVAX"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        IWormhole wormholeContract = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormholeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), "wrong chainId");
        require(wormholeContract.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE_AVAX"), "wrong messageFee");
        require(
            wormholeContract.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX_AVAX")),
            "wrong guardian set index"
        );

        // set up Token Bridge
        ITokenBridge tokenBridgeContract = ITokenBridge(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX"));

        // verify Token Bridge state from fork
        require(tokenBridgeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), "wrong chainId");
        

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        uint256 interestAccrualIndexPrecision = 10 ** 18;
        uint256 collateralizationRatioPrecision = 10 ** 18;
        uint8 initialMaxDecimals = 24;
        uint256 maxLiquidationBonus = 105 * 10**16;
        uint256 maxLiquidationPortion = 100;
        uint256 maxLiquidationPortionPrecision = 100;
        uint8 oracleMode = 1;
        uint64 nConf = 424;
        uint64 nConfPrecision = 100;
        address pythAddress = vm.envAddress("TESTING_PYTH_ADDRESS_AVAX");

        Hub hub =
        new Hub(
            address(wormholeContract), 
            address(tokenBridgeContract), 
            pythAddress, 
            oracleMode,
            wormholeFinality, 
            interestAccrualIndexPrecision, 
            collateralizationRatioPrecision, 
            initialMaxDecimals, 
            maxLiquidationBonus, 
            maxLiquidationPortion, 
            maxLiquidationPortionPrecision,
            nConf,
            nConfPrecision
        );

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
        
        registerChainOnHub(6, bytes32(uint256(uint160(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")))));

    }

    function doRegisterSpoke(uint256 index) internal returns (Spoke) {

        SpokeData memory spokeData = getSpokeData(index);
        // register asset
        getHub().registerSpoke(
            spokeData.foreignChainId, address(spokeData.spoke)
        );

        return spokeData.spoke;
    }

    function doRegisterAsset(uint256 spokeIndex, Asset memory asset) internal {
        Vm vm = getVm();
        
        uint256 reservePrecision = 1 * 10**18;
        
        // register asset
        vm.recordLogs();
        getHub().registerAsset(
            asset.assetAddress, asset.collateralizationRatioDeposit, asset.collateralizationRatioBorrow, asset.reserveFactor, reservePrecision, asset.pythId, asset.decimals
        );
        
        AssetInfo memory info = getHub().getAssetInfo(asset.assetAddress);

        require(
            (info.collateralizationRatioDeposit == asset.collateralizationRatioDeposit) && (info.collateralizationRatioBorrow == asset.collateralizationRatioBorrow) && (info.decimals == asset.decimals) && (info.pythId == asset.pythId) && (info.exists) && (info.interestRateModel.ratePrecision == 1 * 10 ** 18) && (info.interestRateModel.rateIntercept == 0) && (info.interestRateModel.rateCoefficientA == 0) && (info.interestRateModel.reserveFactor == asset.reserveFactor) && (info.interestRateModel.reservePrecision == reservePrecision),
            "didn't register properly" 
        );
    }
   
    function doAction(ActionParameters memory params) internal {
        Action action = Action(params.action);
        requireAssetAmountValidForTokenBridge(params.assetAddress, params.assetAmount);
        Spoke spoke = getSpoke(params.spokeIndex);
        address vault = address(this);
        if(params.prank) {
            vault = params.prankAddress;
        }
        Vm vm = getVm();
        ActionStateData memory beforeData = getActionStateData(vault, params.assetAddress);
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
            spoke.depositCollateral(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Repay) {
            spoke.repay(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Borrow) {
            spoke.borrow(params.assetAddress, params.assetAmount);
        }
        else if(action == Action.Withdraw) {
            spoke.withdrawCollateral(params.assetAddress, params.assetAmount);
        }
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(params.spokeIndex, entries[entries.length - 1]);

        if(params.expectRevert) {
            vm.expectRevert(bytes(params.revertString));
        }
        if(action == Action.Deposit) {
            getHub().completeDeposit(encodedMessage);
        }
        else if(action == Action.Repay) {
            getHub().completeRepay(encodedMessage);
        }
        else if(action == Action.Borrow) {
            getHub().completeBorrow(encodedMessage);
        }
        else if(action == Action.Withdraw) {
            getHub().completeWithdraw(encodedMessage);
        }
        if(params.expectRevert) {
            return;
        }

        if(action == Action.Borrow || action == Action.Withdraw) {
            entries = vm.getRecordedLogs();
            encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);
            getHubData().tokenBridgeContract.completeTransfer(encodedMessage);
        }

        ActionStateData memory afterData = getActionStateData(vault, params.assetAddress);

        requireActionDataValid(action, params.assetAmount, beforeData, afterData);
    }

    
    function doDeposit(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doAction(ActionParameters({
            action: Action.Deposit,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
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
            prank: false,
            prankAddress: address(0x0)
        }));
    }
    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: false,
            revertString: "",
            prank: true,
            prankAddress: vault
        }));
    }
    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doAction(ActionParameters({
            action: Action.Repay,
            spokeIndex: spokeIndex,
            assetAddress: asset.assetAddress,
            assetAmount: assetAmount,
            expectRevert: true,
            revertString: revertString,
            prank: false,
            prankAddress: address(0x0)
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
            prank: false,
            prankAddress: address(0x0)
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
            prank: false,
            prankAddress: address(0x0)
        }));
    }
 
    function setPrice(Asset memory asset, int64 price) internal {
       setPrice(asset, price, 0, 0, 100, 100);
    }

    function setPrice(Asset memory asset, int64 price, uint64 conf, int32 expo, int64 emaPrice, uint64 emaConf) internal {
        // TODO: Double check publish time is correct

        uint64 publishTime = getPublishTime();
        publishTime += 1;
        setPublishTime(publishTime);
        
        if(getHub().getOracleMode() == 1){
            getHub().setMockPythFeed(asset.pythId, price, conf, expo, emaPrice, emaConf, publishTime);
        }
        else if(getHub().getOracleMode() == 2){
            getHub().setOraclePrice(asset.pythId, Price({price: price, conf: conf, expo: expo, publishTime: publishTime}));
        }
    }

}
