// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestGetters is TestStructs, TestState {
    
    function getHubData() internal view returns (HubData) {
        return _state.hubData;
    }

    function getHub() internal view returns (Hub) {
        return _state.hubData.hub;
    }

    function getSpokeData(uint256 index) internal view returns (SpokeData) {
        return _state.spokeDatas[index];
    }

    function getSpoke(uint256 index) internal view returns (Spoke) {
        return _state.spokeDatas[index].spoke;
    }

    function getAsset(uint256 index) internal view returns (Asset) {
        return _state.assets[index];
    }

    function getAssetAddress(uint256 index) internal view returns (address) {
        return _state.assets[index].assetAddress;
    }

    function getVm() internal view returns (Vm) {
        return _state.vm;
    }

    function getPublishTime() internal view returns (uint64) {
        return _state.publishTime;
    }

}
