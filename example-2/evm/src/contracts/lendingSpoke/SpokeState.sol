// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lendingHub/HubStructs.sol";

contract SpokeStorage is HubStructs {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        address tokenBridge;
    }

    struct State {
        Provider provider;

        // contract deployer
        address owner;

        // number of confirmations for wormhole messages
        uint8 consistencyLevel;

        // allowlist for assets
        address[] allowList;

        // address => AssetInfo
        mapping(address => AssetInfo) assetInfos;

        uint16 hubChainId;

        address hubContractAddress;

        // wormhole message hashes
        mapping(bytes32 => bool) consumedMessages;

        // @dev storage gap
        uint256[50] ______gap;
    }
}

contract SpokeState {
    SpokeStorage.State _state;
}