// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";

contract SpokeStorage is HubSpokeStructs {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        address tokenBridge;
    }

    struct State {
        Provider provider;
        // number of confirmations for wormhole messages
        uint8 consistencyLevel;
        uint16 hubChainId;
        address hubContractAddress;
        // @dev storage gap
        uint256[50] ______gap;
    }
}

contract SpokeState {
    SpokeStorage.State _state;
}
