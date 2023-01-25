// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";

contract TestGetters is TestStructs, TestState {
    
    function getHubData() internal view returns (HubData memory) {
        return _testState.hubData;
    }

    function getHub() internal view returns (Hub) {
        return _testState.hubData.hub;
    }

    function getSpokeData(uint256 index) internal view returns (SpokeData memory) {
        return _testState.spokeDatas[index];
    }

    function getSpoke(uint256 index) internal view returns (Spoke) {
        return _testState.spokeDatas[index].spoke;
    }

    function getAsset(uint256 index) internal view returns (Asset memory) {
        return _testState.assets[index];
    }

    function getAssetAddress(uint256 index) internal view returns (address) {
        return _testState.assets[index].assetAddress;
    }

    function getVm() internal view returns (Vm) {
        return _testState.vm;
    }

    function getPublishTime() internal view returns (uint64) {
        return _testState.publishTime;
    }

    function getOracleMode() internal view returns(uint8) {
        return _testState.oracleMode;
    }

    function getDebug() internal view returns(bool) {
        return _testState.debug;
    }

}
