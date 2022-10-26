// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../lendingHub/HubStructs.sol";
import "./SpokeState.sol";
import "./SpokeGetters.sol";
import "./SpokeSetters.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SpokeUtilities is Context, HubStructs, SpokeState, SpokeGetters, SpokeSetters {
    
    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function sendTokenBridgeMessage(address assetAddress, uint256 assetAmount, bytes memory payload) internal {
        SafeERC20.safeApprove(IERC20(assetAddress), tokenBridgeAddress(), assetAmount);
        tokenBridge().transferTokensWithPayload(
            assetAddress, assetAmount, hubChainId(), bytes32(uint256(uint160(hubContractAddress()))), 0, payload
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

     /**
    * Check if an address has been registered on the Hub yet (through the registerAsset function)
    * Errors out if assetAddress has not been registered yet
    * @param assetAddress - The address to be checked
    */
    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(registered_info.exists, "Unregistered asset");
    }
}
