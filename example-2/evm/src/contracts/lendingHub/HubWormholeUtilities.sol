// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../libraries/external/BytesLib.sol";

import "../../interfaces/IWormhole.sol";

import "./HubGetters.sol";
import "./HubSetters.sol";


contract HubWormholeUtilities is HubGetters, HubSetters {
    using BytesLib for bytes;


    function transferTokens(address receiver, address assetAddress, uint256 amount, uint16 recipientChain) internal returns (uint64 sequence) {
        SafeERC20.safeApprove(IERC20(assetAddress), tokenBridgeAddress(), amount);
        sequence = tokenBridge().transferTokens(assetAddress, amount, recipientChain, bytes32(uint256(uint160(receiver))), 0, 0);
    }

    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function getTransferPayload(bytes memory encodedMessage) internal returns (bytes memory payload) {
        (IWormhole.VM memory parsed,,) = wormhole().parseAndVerifyVM(encodedMessage);

        verifySenderIsSpoke(
            parsed.emitterChainId, address(uint160(uint256(parsed.payload.toBytes32(1 + 32 + 32 + 2 + 32 + 2))))
        );

        payload = tokenBridge().completeTransferWithPayload(encodedMessage);
    }

    function getWormholeParsed(bytes memory encodedMessage) internal returns (IWormhole.VM memory) {
        (IWormhole.VM memory parsed, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        require(!messageHashConsumed(parsed.hash), "message already consumed");
        consumeMessageHash(parsed.hash);

        return parsed;
    }

    function extractPayloadFromTransferPayload(bytes memory encodedVM) internal pure returns (bytes memory serialized) {
        uint256 index = 0;
        uint256 end = encodedVM.length;

        // pass through TransferWithPayload metadata to arbitrary serialized bytes
        index += 1 + 32 + 32 + 2 + 32 + 2 + 32;

        return encodedVM.slice(index, end - index);
    }

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {
        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

}
