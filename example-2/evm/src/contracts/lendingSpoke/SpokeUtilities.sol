// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../lendingHub/HubStructs.sol";
import "./SpokeState.sol";
import "./SpokeGetters.sol";
import "./SpokeSetters.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";


contract SpokeUtilities is Context, HubStructs, SpokeState, SpokeGetters, SpokeSetters {
    
    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function sendTokenBridgeMessage(address assetAddress, uint256 assetAmount, bytes memory payload) internal {

        SafeERC20.safeTransferFrom(IERC20(assetAddress), msg.sender, address(this), assetAmount);

        SafeERC20.safeApprove(IERC20(assetAddress), tokenBridgeAddress(), assetAmount);

        // TODO: Do we need to check some sort of maximum limit of assetAmount
        tokenBridge().transferTokensWithPayload(
            assetAddress, assetAmount, hubChainId(), bytes32(uint256(uint160(hubContractAddress()))), 0, payload
        );
    }

    function sendTokenBridgeMessageNative(uint amount, bytes memory payload) internal {
        tokenBridge().wrapAndTransferETHWithPayload{value: amount}(
            hubChainId(), bytes32(uint256(uint160(hubContractAddress()))), 0, payload
        );
    }

    function getWormholePayload(bytes calldata encodedMessage) internal returns (bytes memory) {
        (IWormhole.VM memory parsed, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        require(
            (hubChainId() == parsed.emitterChainId)
                && (hubContractAddress() == address(uint160(uint256(parsed.emitterAddress)))),
            "Not from Hub"
        );

        require(!messageHashConsumed(parsed.hash), "message already consumed");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    }

  
    function requireAssetAmountValidForTokenBridge(address assetAddress, uint256 assetAmount) internal view {
        (,bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        require(deNormalizeAmount(normalizeAmount(assetAmount, decimals), decimals) == assetAmount, "Too many decimal places");
    }

    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }
}
