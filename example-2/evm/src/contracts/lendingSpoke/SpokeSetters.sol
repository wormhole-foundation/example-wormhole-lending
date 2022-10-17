// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SpokeState.sol";
import "../lendingHub/HubStructs.sol";


contract SpokeSetters is SpokeState, HubStructs {
    function setOwner(address owner) internal {
        _state.owner = owner;
    }

    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setWormhole(address wormholeAddress) internal {
        _state.provider.wormhole = payable(wormholeAddress);
    }

    function setTokenBridge(address tokenBridgeAddress) internal {
        _state.provider.tokenBridge = tokenBridgeAddress;
    }

    function registerAssetInfo(address assetAddress, AssetInfo memory info) internal {
        _state.assetInfos[assetAddress] = info;
    }

    function allowAsset(address assetAddress) internal {
        _state.allowList.push(assetAddress);
    }
}