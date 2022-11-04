// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TestStructs} from "./TestStructs.sol";


// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestStorage is TestStructs {
    struct State {
        HubData hubData;
        SpokeData[] spokeDatas;
        Asset[] assets;
        Vm vm;
        uint64 publishTime;
    }
}

contract TestState {
    TestStorage.State _testState;
}