// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract SpokeStorage {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        address tokenBridge;
    }

    struct State {
        Provider provider;

        /// contract deployer
        address owner;

        /// number of confirmations for wormhole messages
        uint8 consistencyLevel;

        /// @dev storage gap
        uint256[50] ______gap;
    }
}

contract SpokeState {
    SpokeStorage.State _state;
}