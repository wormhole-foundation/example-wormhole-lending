// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SpokeState.sol";
import "../HubSpokeStructs.sol";

contract SpokeSetters is HubSpokeStructs, SpokeState {
    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setWormhole(address wormholeAddress) internal {
        _state.provider.wormhole = payable(wormholeAddress);
    }

    function setTokenBridge(address tokenBridgeAddress) internal {
        _state.provider.tokenBridge = tokenBridgeAddress;
    }

    function setHubChainId(uint16 hubChainId) internal {
        _state.hubChainId = hubChainId;
    }

    function setHubContractAddress(address hubContractAddress) internal {
        _state.hubContractAddress = hubContractAddress;
    }
}
