// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";
import "./SpokeState.sol";
import "./SpokeGetters.sol";
import "./SpokeSetters.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SpokeUtilities is HubSpokeStructs, SpokeState, SpokeGetters, SpokeSetters {
    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function sendTokenBridgeMessage(address assetAddress, uint256 assetAmount, bytes memory payload)
        internal
        returns (uint64 sequence)
    {
        SafeERC20.safeTransferFrom(IERC20(assetAddress), msg.sender, address(this), assetAmount);

        SafeERC20.safeApprove(IERC20(assetAddress), tokenBridgeAddress(), assetAmount);

        sequence = tokenBridge().transferTokensWithPayload(
            assetAddress, assetAmount, hubChainId(), bytes32(uint256(uint160(hubContractAddress()))), 0, payload
        );
    }

    function sendTokenBridgeMessageNative(uint256 amount, bytes memory payload) internal returns (uint64 sequence) {
        sequence = tokenBridge().wrapAndTransferETHWithPayload{value: amount}(
            hubChainId(), bytes32(uint256(uint160(hubContractAddress()))), 0, payload
        );
    }

    function requireAssetAmountValidForTokenBridge(address assetAddress, uint256 assetAmount) internal view {
        (, bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        require(
            deNormalizeAmount(normalizeAmount(assetAmount, decimals), decimals) == assetAmount,
            "Too many decimal places"
        );
    }

    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }
}
