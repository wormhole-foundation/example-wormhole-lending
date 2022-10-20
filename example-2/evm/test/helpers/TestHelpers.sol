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
    struct TestToken {
        address tokenAddress;
        IERC20 token;
        uint256 collateralizationRatio;
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

    using BytesLib for bytes;

    function testSetUp(Vm vm, TestToken[] storage tokens) internal returns (WormholeData memory, WormholeSpokeData memory) {
        // initialize tokens with above tokens
        
        tokens.push(TestToken({
                tokenAddress: 0x442F7f22b1EE2c842bEAFf52880d4573E9201158,
                token: IERC20(0x442F7f22b1EE2c842bEAFf52880d4573E9201158),
                collateralizationRatio: 110000000000000000000
            }));

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
        uint256 interestAccrualIndexPrecision = 1000000000000000000;
        Hub hub =
        new Hub(address(wormholeContract), address(tokenBridgeContract), msg.sender, wormholeFinality, interestAccrualIndexPrecision);

        WormholeData memory wormholeData = WormholeData({
            guardianSigner: guardianSigner,
            wormholeSimulator: wormholeSimulator,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            hub: hub,
            vm: vm
        });

        WormholeSpokeData memory wormholeSpokeData =
            WormholeSpokeData({foreignTokenBridgeAddress: foreignTokenBridgeAddress, foreignChainId: foreignChainId});

        return (wormholeData, wormholeSpokeData);
    }

    function encodePayload3Message(
        ITokenBridge.TransferWithPayload memory transfer,
        // wormhole related
        IWormhole.WormholeBodyParams memory wormholeParams
    ) public returns (bytes memory encoded) {
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
    ) public returns (bytes memory encodedVm) {
        encodedVm = abi.encodePacked(
            version, timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload
        );
    }

    function getWrappedInfo(address assetAddress) internal returns (ITokenImplementation wrapped) {
        //
        wrapped = ITokenImplementation(assetAddress);
        console.log("wrapped chain id", wrapped.chainId());
        console.log("wrapped native contract");
        console.logBytes32(wrapped.nativeContract());
    }

    function getSignedWHMsg(
        ITokenBridge.TransferWithPayload memory transfer,
        WormholeData memory wormholeData,
        WormholeSpokeData memory wormholeSpokeData
    ) internal returns (bytes memory encodedVM) {
        //  construct WH message
        bytes memory message = encodePayload3Message(
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
    function doRegister(
        address assetAddress,
        uint256 collateralizationRatio,
        uint256 reserveFactor,
        bytes32 pythId,
        uint8 decimals,
        WormholeData memory wormholeData,
        WormholeSpokeData memory wormholeSpokeData
    ) internal {
        // register asset
        wormholeData.hub.registerAsset(assetAddress, collateralizationRatio, reserveFactor, pythId, decimals);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doDeposit(
        address vault,
        address assetAddress,
        uint256 assetAmount,
        WormholeData memory wormholeData,
        WormholeSpokeData memory wormholeSpokeData
    ) internal returns (bytes memory encodedVM) {
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

        encodedVM = getSignedWHMsg(transfer, wormholeData, wormholeSpokeData);

        // complete deposit
        wormholeData.hub.completeDeposit(encodedVM);
    }
}
