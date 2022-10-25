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

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../../src/interfaces/ITokenImplementation.sol";

import "../../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestHelpers is HubStructs, HubMessages, HubGetters, HubUtilities {
    struct TestAsset {
        address assetAddress;
        IERC20 asset;
        uint256 collateralizationRatio;
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
    }

    WormholeData wormholeData;
    WormholeSpokeData wormholeSpokeData;

    using BytesLib for bytes;

    function setSpokeData(bytes32 foreignTokenBridgeAddress, uint16 foreignChainId) internal {
        wormholeSpokeData = WormholeSpokeData({foreignTokenBridgeAddress: foreignTokenBridgeAddress, foreignChainId: foreignChainId});
    }

    function testSetUp(Vm vm) internal returns (Hub hub) {
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
        bytes32 foreignTokenBridgeAddress = vm.envBytes32("TESTING_FOREIGN_TOKEN_BRIDGE_ADDRESS");
        uint16 foreignChainId = uint16(vm.envUint("TESTING_FOREIGN_CHAIN_ID"));

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        uint256 interestAccrualIndexPrecision = 10 ** 18;
        uint256 collateralizationRatioPrecision = 10 ** 18;
        uint8 initialMaxDecimals = 24;
        hub =
        new Hub(address(wormholeContract), address(tokenBridgeContract), msg.sender, wormholeFinality, interestAccrualIndexPrecision, collateralizationRatioPrecision, initialMaxDecimals);

        wormholeData = WormholeData({
            guardianSigner: guardianSigner,
            wormholeSimulator: wormholeSimulator,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            hub: hub,
            vm: vm
        });

        setSpokeData(foreignTokenBridgeAddress, foreignChainId);
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
                emitterChainId: wormholeSpokeData.foreignChainId,
                emitterAddress: wormholeSpokeData.foreignTokenBridgeAddress,
                sequence: 1,
                consistencyLevel: 15
            })
        );
    }

    function getSignedWHMsgCoreBridge(bytes memory payload) internal returns (bytes memory encodedVM) {
        bytes memory message = abi.encodePacked(
            uint32(0),
            uint32(0),
            wormholeSpokeData.foreignChainId,
            wormholeSpokeData.foreignTokenBridgeAddress, // TODO: Fix this address; this should be the spoke address
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

    // TODO: Do we need this? Maybe remove this helper function
    function doRegisterSpoke() internal {
        // register asset
        wormholeData.hub.registerSpoke(
            wormholeSpokeData.foreignChainId, address(uint160(uint256(wormholeSpokeData.foreignTokenBridgeAddress)))
        );
    }

    // TODO: Do we need this? Maybe remove this helper function
    function doRegister(TestAsset memory asset) internal {
        // register asset
        wormholeData.hub.registerAsset(
            asset.assetAddress, asset.collateralizationRatio, asset.reserveFactor, asset.pythId, asset.decimals
        );
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doDeposit(address vault, TestAsset memory asset, uint256 assetAmount)
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
        wormholeData.hub.completeDeposit(encodedVM);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doRepay(address vault, TestAsset memory asset, uint256 assetAmount)
        internal
        returns (bytes memory encodedVM)
    {
        address assetAddress = asset.assetAddress;
        // create Deposit payload
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

        // complete deposit
        wormholeData.hub.completeRepay(encodedVM);
    }

    // create Borrow payload and package it into TokenBridgePayload into WH message and send the borrow
    function doBorrow(address vault, TestAsset memory asset, uint256 assetAmount)
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
        wormholeData.hub.completeBorrow(encodedVM);
    }

    // create Withdraw payload and package it into TokenBridgePayload into WH message and send the withdraw
    function doWithdraw(address vault, TestAsset memory asset, uint256 assetAmount)
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
        wormholeData.hub.completeWithdraw(encodedVM);
    }

    function setPrice(TestAsset memory asset, int64 price) internal {
        wormholeData.hub.setOraclePrice(asset.pythId, Price({price: price, conf: 10, expo: 1, publishTime: 1}));
    }
}
