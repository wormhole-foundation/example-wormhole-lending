// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../../src/interfaces/ITokenImplementation.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestSetters} from "./TestSetters.sol";
import {TestGetters} from "./TestGetters.sol";


import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestUtilities is TestStructs, TestState, TestGetters, TestSetters {
    
    function fetchSignedMessageFromSpokeLogs(uint256 spokeIndex, Vm.Log memory entry) internal returns (bytes memory) {
        return getSpokeData(spokeIndex).wormholeSimulator.fetchSignedMessageFromLogs(entry);
    }

    function fetchSignedMessageFromHubLogs(Vm.Log memory entry) internal returns (bytes memory) {
        return getHubData().wormholeSimulator.fetchSignedMessageFromLogs(entry);
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

    function encodePayload1Message(
        ITokenBridge.Transfer memory transfer,
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
                transfer.fee
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
        wrapped = ITokenImplementation(assetAddress);
    }

    function getMessageFromTransferTokenBridge(
        ITokenBridge.TransferWithPayload memory transfer
    ) internal returns (bytes memory message) {
        message = encodePayload3Message(
            transfer,
            IWormhole.WormholeBodyParams({
                timestamp: 0,
                nonce: 0,
                emitterChainId: uint16(getVm().envUint("TESTING_WORMHOLE_CHAINID_AVAX")),
                emitterAddress: bytes32(uint256(uint160(getVm().envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")))),
                sequence: 1,
                consistencyLevel: 15
            })
        );
    }

    function getMessageFromTransferTokenBridge(
        ITokenBridge.Transfer memory transfer
    ) internal returns (bytes memory message) {
        message = encodePayload1Message(
            transfer,
            IWormhole.WormholeBodyParams({
                timestamp: 0,
                nonce: 0,
                emitterChainId: uint16(getVm().envUint("TESTING_WORMHOLE_CHAINID_AVAX")),
                emitterAddress: bytes32(uint256(uint160(getVm().envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")))),
                sequence: 1,
                consistencyLevel: 15
            })
        );
    }

    function getSignedWHMsgCoreBridge(bytes memory payload) internal returns (bytes memory encodedVM) {
        bytes memory message = abi.encodePacked(
            uint32(0),
            uint32(0),
            uint16(getVm().envUint("TESTING_WORMHOLE_CHAINID_AVAX")),
            bytes32(uint256(uint160(address(this)))), // this should be the spoke address
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

    function getSignedWHMsgTransferTokenBridge(ITokenBridge.Transfer memory transfer)
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
        (sigs[0].v, sigs[0].r, sigs[0].s) = getVm().sign(getHubData().guardianSigner, messageHash);
        sigs[0].guardianIndex = 0;

        encodedVM = abi.encodePacked(
            uint8(1), // version
            getHubData().wormholeContract.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            message
        );
    }

    function registerChainOnHub(uint16 emitterChainId, bytes32 emitterAddress) internal returns (bytes memory) {
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

        getHubData().tokenBridgeContract.registerChain(registerChainSignedMsg);
        
    }

    function normalizeAmountWithinTokenBridge(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function requireAssetAmountValidForTokenBridge(address assetAddress, uint256 assetAmount) internal {
        (,bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        require(deNormalizeAmountWithinTokenBridge(normalizeAmountWithinTokenBridge(assetAmount, decimals), decimals) == assetAmount, "Too many decimal places");
    }

    function deNormalizeAmountWithinTokenBridge(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }


}
