// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../../src/contracts/lendingHub/HubMessages.sol";
import {HubUtilities} from "../../src/contracts/lendingHub/HubUtilities.sol";
import {MyERC20} from "./MyERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../../src/interfaces/ITokenImplementation.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";

import "../../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestHelpers is HubStructs, HubMessages, HubGetters, HubUtilities {
    struct TestAsset {
        address assetAddress;
        IERC20 asset;
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        
        uint8 decimals;
        uint256 reserveFactor;
        bytes32 pythId;
    }

    struct WormholeData {
        Hub hub;
        IWormhole wormholeContract;
        ITokenBridge tokenBridgeContract;
        uint256 guardianSigner;
        WormholeSimulator wormholeSimulator;
        Vm vm;
    }

    struct WormholeSpokeData {
        bytes32 foreignTokenBridgeAddress;
        uint16 foreignChainId;
        IWormhole wormholeContract;
        ITokenBridge tokenBridgeContract;
        WormholeSimulator wormholeSimulator;
        Spoke spoke;
    }

    WormholeData wormholeData;
    WormholeSpokeData[] wormholeSpokeDataArray;
    WormholeSpokeData wormholeSpokeData;

    using BytesLib for bytes;

    function setSpokeData(uint256 index) internal returns (WormholeSpokeData memory) {
        wormholeSpokeData = wormholeSpokeDataArray[index];
    }

    function getSpoke(uint256 index) internal returns (Spoke spoke) {
        return wormholeSpokeDataArray[index].spoke;
    }

    function addSpoke(uint16 chainId, address wormholeAddress, address tokenBridgeAddress) internal {
        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(wormholeAddress, wormholeData.guardianSigner);
        IWormhole wormholeContract = wormholeSimulator.wormhole();
        ITokenBridge tokenBridgeContract = ITokenBridge(tokenBridgeAddress);

        uint16 hubChainId = uint16(wormholeData.vm.envUint("TESTING_WORMHOLE_CHAINID"));
        Spoke spoke = new Spoke(chainId, wormholeAddress, tokenBridgeAddress, hubChainId, address(wormholeData.hub));
        wormholeSpokeDataArray.push(WormholeSpokeData({
            foreignTokenBridgeAddress: bytes32(uint256(uint160(tokenBridgeAddress))),
            foreignChainId: chainId,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            wormholeSimulator: wormholeSimulator,
            spoke: spoke
        }));
    }   

    function fetchSignedMessageFromLogs(Vm.Log memory entry) internal returns (bytes memory) {
        return wormholeSpokeData.wormholeSimulator.fetchSignedMessageFromLogs(entry);
    }
    function testSetUp(Vm vm) internal returns (Hub) {
        // initialize assets with above assets

        // this will be used to sign wormhole messages
        uint256 guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        // set up Wormhole using Wormhole existing
        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        IWormhole wormholeContract = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormholeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID")), "wrong chainId");
        require(wormholeContract.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE"), "wrong messageFee");
        require(
            wormholeContract.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX")),
            "wrong guardian set index"
        );

        // set up Token Bridge
        ITokenBridge tokenBridgeContract = ITokenBridge(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS"));

        // verify Token Bridge state from fork
        require(tokenBridgeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID")), "wrong chainId");

        // foreign token bridge (ethereum)
        //bytes32 foreignTokenBridgeAddress = vm.envBytes32("TESTING_FOREIGN_TOKEN_BRIDGE_ADDRESS");
        //uint16 foreignChainId = uint16(vm.envUint("TESTING_FOREIGN_CHAIN_ID"));

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        uint256 interestAccrualIndexPrecision = 10 ** 18;
        uint256 collateralizationRatioPrecision = 10 ** 18;
        uint8 initialMaxDecimals = 24;
        uint256 maxLiquidationBonus = 105 * 10**16;
        uint256 maxLiquidationPortion = 100;
        uint256 maxLiquidationPortionPrecision = 100;
        //console.log(address(wormholeContract));
        //console.log(address(tokenBridgeContract));

        Hub hub =
        new Hub(address(wormholeContract), address(tokenBridgeContract), msg.sender, wormholeFinality, interestAccrualIndexPrecision, collateralizationRatioPrecision, initialMaxDecimals, maxLiquidationBonus, maxLiquidationPortion, maxLiquidationPortionPrecision);

        wormholeData = WormholeData({
            guardianSigner: guardianSigner,
            wormholeSimulator: wormholeSimulator,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            hub: hub,
            vm: vm
        });

        registerChain(6, bytes32(uint256(uint160(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS")))));

      
        return hub;
    }

    

    function encodePayload3Message(
        ITokenBridge.TransferWithPayload memory transfer,
        // wormhole related
        IWormhole.WormholeBodyParams memory wormholeParams
    ) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            wormholeParams.timestamp,
            wormholeParams.nonce,
            wormholeParams.emitterChainId,
            wormholeParams.emitterAddress,
            wormholeParams.sequence,
            wormholeParams.consistencyLevel,
            abi.encodePacked(
                transfer.payloadID,
                transfer.amount,
                transfer.tokenAddress,
                transfer.tokenChain,
                transfer.to,
                transfer.toChain,
                transfer.fromAddress,
                transfer.payload
            )
        );
    }

    function encodeVM(
        uint8 version,
        uint32 timestamp,
        uint32 nonce,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        uint8 consistencyLevel,
        bytes calldata payload
    ) public pure returns (bytes memory encodedVm) {
        encodedVm = abi.encodePacked(
            version, timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload
        );
    }

    function getWrappedInfo(address assetAddress) internal pure returns (ITokenImplementation wrapped) {
        //
        wrapped = ITokenImplementation(assetAddress);
        //console.log("wrapped chain id", wrapped.chainId());
        //console.log("wrapped native contract");
        //console.logBytes32(wrapped.nativeContract());
    }

    function getMessageFromTransferTokenBridge(
        ITokenBridge.TransferWithPayload memory transfer
    ) internal view returns (bytes memory message) {
        message = encodePayload3Message(
            transfer,
            IWormhole.WormholeBodyParams({
                timestamp: 0,
                nonce: 0,
                emitterChainId: 2,
                emitterAddress: 0x0000000000000000000000003ee18b2214aff97000d974cf647e7c347e8fa585,
                sequence: 1,
                consistencyLevel: 15
            })
        );
    }

    function getSignedWHMsgCoreBridge(bytes memory payload) internal returns (bytes memory encodedVM) {
        bytes memory message = abi.encodePacked(
            uint32(0),
            uint32(0),
            uint16(2),
            bytes32(uint256(uint160(address(0x1)))), // this should be the spoke address
            uint64(1),
            uint8(15),
            payload
        );

        encodedVM = getSignedWHMsg(message);
    }

    function getSignedWHMsgTransferTokenBridge(ITokenBridge.TransferWithPayload memory transfer)
        internal
        returns (bytes memory encodedVM)
    {
        bytes memory message = getMessageFromTransferTokenBridge(transfer);

        encodedVM = getSignedWHMsg(message);
    }

    function getSignedWHMsg(bytes memory message)
        internal
        returns (bytes memory encodedVM)
    {
        // get hash for signature
        bytes32 messageHash = keccak256(abi.encodePacked(keccak256(message)));

        // Sign the hash with the devnet guardian private key
        IWormhole.Signature[] memory sigs = new IWormhole.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = wormholeData.vm.sign(wormholeData.guardianSigner, messageHash);
        sigs[0].guardianIndex = 0;

        encodedVM = abi.encodePacked(
            uint8(1), // version
            wormholeData.wormholeContract.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            message
        );
    }

    function doRegisterSpoke(uint256 index) internal returns (Spoke) {
        setSpokeData(index);
        // register asset
        wormholeData.hub.registerSpoke(
            wormholeSpokeData.foreignChainId, address(wormholeSpokeData.spoke)
        );

        return wormholeSpokeData.spoke;
    }

    function doRegisterSpoke_FS() internal {
        // register asset
        wormholeData.hub.registerSpoke(
            2, address(0x1)
        );
    }

    function doRegisterAsset(TestAsset memory asset) internal returns (bytes memory) {
        uint256 reservePrecision = 1 * 10**18;

        // register asset
        wormholeData.vm.recordLogs();
        wormholeData.hub.registerAsset(
            asset.assetAddress, asset.collateralizationRatioDeposit, asset.collateralizationRatioBorrow, asset.reserveFactor, reservePrecision, asset.pythId, asset.decimals
        );
        Vm.Log[] memory entries = wormholeData.vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromLogs(entries[entries.length - 1]);
        return encodedMessage;
    }

    function doDeposit(uint256 spokeIndex, TestAsset memory asset, uint256 assetAmount) internal returns (bytes memory) {
        setSpokeData(spokeIndex);
        wormholeData.vm.recordLogs();
        wormholeSpokeData.spoke.depositCollateral(asset.assetAddress, assetAmount);
        Vm.Log[] memory entries = wormholeData.vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromLogs(entries[entries.length - 1]);
        return encodedMessage;
    }

    function doDeposit_FS(address vault, TestAsset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doDeposit_FS(vault, asset, assetAmount, false, "");
    }

    function doDeposit_FS(address vault, TestAsset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doDeposit_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doDeposit_FS(address vault, TestAsset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
        returns (bytes memory encodedVM)
    {
        address assetAddress = asset.assetAddress;
        // create Deposit payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        DepositPayload memory myPayload =
            DepositPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeDepositPayload(myPayload);
      
        // get wrapped info
        ITokenImplementation wrapped = getWrappedInfo(assetAddress);
    

        // TokenBridgePayload
        ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
            payloadID: 3,
            amount: assetAmount,
            tokenAddress: wrapped.nativeContract(),
            tokenChain: wrapped.chainId(),
            to: bytes32(uint256(uint160(address(wormholeData.hub)))),
            toChain: wormholeData.wormholeContract.chainId(),
            fromAddress: bytes32(uint256(uint160(msg.sender))),
            payload: serialized
        });
     
        encodedVM = getSignedWHMsgTransferTokenBridge(transfer);
       
        // complete deposit
        if(expectRevert) {
            wormholeData.vm.expectRevert(bytes(revertString));
        }
        wormholeData.hub.completeDeposit(encodedVM);
        
    }

    function doRepay_FS(address vault, TestAsset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doRepay_FS(vault, asset, assetAmount, false, "");
    }

    function doRepay_FS(address vault, TestAsset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doRepay_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doRepay_FS(address vault, TestAsset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
        returns (bytes memory encodedVM)
    {
        address assetAddress = asset.assetAddress;
        // create Repay payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(4),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        RepayPayload memory myPayload =
            RepayPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeRepayPayload(myPayload);

        // get wrapped info
        ITokenImplementation wrapped = getWrappedInfo(assetAddress);


        // TokenBridgePayload
        ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
            payloadID: 3,
            amount: assetAmount,
            tokenAddress: wrapped.nativeContract(),
            tokenChain: wrapped.chainId(),
            to: bytes32(uint256(uint160(address(wormholeData.hub)))),
            toChain: wormholeData.wormholeContract.chainId(),
            fromAddress: bytes32(uint256(uint160(msg.sender))),
            payload: serialized
        });

        encodedVM = getSignedWHMsgTransferTokenBridge(transfer);

        // complete repay
        if(expectRevert) {
            wormholeData.vm.expectRevert(bytes(revertString));
        }
        wormholeData.hub.completeRepay(encodedVM);
    }

    function doBorrow_FS(address vault, TestAsset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doBorrow_FS(vault, asset, assetAmount, false, "");
    }

    function doBorrow_FS(address vault, TestAsset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doBorrow_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Borrow payload and package it into TokenBridgePayload into WH message and send the borrow
    function doBorrow_FS(address vault, TestAsset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
        returns (bytes memory encodedVM)
    {
        address assetAddress = asset.assetAddress;
        // create Borrow payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(3),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        BorrowPayload memory myPayload =
            BorrowPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeBorrowPayload(myPayload);

        // // get wrapped info
        // ITokenImplementation wrapped = getWrappedInfo(assetAddress);

        // // TokenBridgePayload
        // ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
        //     payloadID: 3,
        //     amount: assetAmount,
        //     tokenAddress: wrapped.nativeContract(),
        //     tokenChain: wrapped.chainId(),
        //     to: bytes32(uint256(uint160(address(wormholeData.hub)))),
        //     toChain: wormholeData.wormholeContract.chainId(),
        //     fromAddress: bytes32(uint256(uint160(msg.sender))),
        //     payload: serialized
        // });

        encodedVM = getSignedWHMsgCoreBridge(serialized);

        // complete borrow
         if(expectRevert) {
            wormholeData.vm.expectRevert(bytes(revertString));
        }
        wormholeData.hub.completeBorrow(encodedVM);
    }

    function doWithdraw_FS(address vault, TestAsset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doWithdraw_FS(vault, asset, assetAmount, false, "");
    }

    function doWithdraw_FS(address vault, TestAsset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doWithdraw_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Withdraw payload and package it into TokenBridgePayload into WH message and send the withdraw
    function doWithdraw_FS(address vault, TestAsset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
        returns (bytes memory encodedVM)
    {
        address assetAddress = asset.assetAddress;
        // create Withdraw payload
        PayloadHeader memory header = PayloadHeader({payloadID: uint8(2), sender: vault});
        WithdrawPayload memory myPayload =
            WithdrawPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeWithdrawPayload(myPayload);

        encodedVM = getSignedWHMsgCoreBridge(serialized);

        // complete withdraw
        if(expectRevert) {
            wormholeData.vm.expectRevert(bytes(revertString));
        }
        wormholeData.hub.completeWithdraw(encodedVM);
    }

    function setPrice(TestAsset memory asset, int64 price) internal {
        wormholeData.hub.setOraclePrice(asset.pythId, Price({price: price, conf: 10, expo: 1, publishTime: 1}));
    }

    struct RegisterChainMessage {
        bytes32 module;
        uint8 action;
        uint16 chainId;
        uint16 emitterChainId;
        bytes32 emitterAddress;
    }

    function registerChain(uint16 emitterChainId, bytes32 emitterAddress) internal returns (bytes memory) {
        RegisterChainMessage memory msg = RegisterChainMessage({
            module: 0x000000000000000000000000000000000000000000546f6b656e427269646765,
            action: 1, 
            chainId: 0,
            emitterChainId: emitterChainId,
            emitterAddress: emitterAddress
        });

        bytes memory payload = abi.encodePacked(
            uint32(0),
            uint32(0),
            uint16(1),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000004), // this should be the spoke address
            uint64(1),
            uint8(15),
            abi.encodePacked(msg.module, msg.action, msg.chainId, msg.emitterChainId, msg.emitterAddress)
        );

        bytes memory registerChainSignedMsg = getSignedWHMsg(payload);

        wormholeData.tokenBridgeContract.registerChain(registerChainSignedMsg);
        
    }

}
