// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./HubState.sol";

contract HubSetters is HubState {
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

    function setPyth(address pythAddress) internal {
        _state.provider.pyth = pythAddress;
    }

    function setConsistencyLevel(uint8 consistencyLevel) internal {
        _state.consistencyLevel = consistencyLevel;
    }

    function registerSpokeContract(uint16 chainId, address spokeContractAddress) internal {
        _state.spokeContracts[chainId] = spokeContractAddress;
    }


}