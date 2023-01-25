// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/external/BytesLib.sol";

import "./HubSpokeStructs.sol";

contract HubSpokeMessages is HubSpokeStructs {
    using BytesLib for bytes;

    function encodeActionPayload(ActionPayload memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(payload.action), payload.sender, payload.assetAddress, payload.assetAmount);
    }

    function decodeActionPayload(bytes memory serialized) internal pure returns (ActionPayload memory params) {
        uint256 index = 0;

        params.action = Action(serialized.toUint8(index));
        index += 1;

        params.sender = serialized.toAddress(index);
        index += 20;

        params.assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAmount = serialized.toUint256(index);
    }
}
