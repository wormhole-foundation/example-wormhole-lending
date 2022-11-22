// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestGetters} from "./TestGetters.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

contract TestSetters is TestStructs, TestState, TestGetters {
    
    function setHubData(HubData memory hubData) internal {
        _testState.hubData = hubData;
    }

    function addSpokeData(SpokeData memory spokeData) internal {
        _testState.spokeDatas.push(spokeData);
    }

    function addAsset(Asset memory asset) internal {
        _testState.assets.push(asset);
    }

    function addAsset(
        AddAsset memory addAssetData
    ) internal {
        (,bytes memory queriedDecimals) = addAssetData.assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        Asset memory asset = Asset({
            assetAddress: addAssetData.assetAddress,
            asset: IERC20(addAssetData.assetAddress),
            collateralizationRatioDeposit: addAssetData.collateralizationRatioDeposit,
            collateralizationRatioBorrow: addAssetData.collateralizationRatioBorrow,
            decimals: decimals,
            ratePrecision: addAssetData.ratePrecision,
            kinks: addAssetData.kinks,
            rates: addAssetData.rates,
            reserveFactor: addAssetData.reserveFactor,
            pythId: addAssetData.pythId
        });
        addAsset(asset);

         int64 startPrice = 0;
            uint64 startConf = 0;
            int32 startExpo = 0;
            int64 startEmaPrice = 0;
            uint64 startEmaConf = 0;
            uint64 startPublishTime = 1;

            getHub().setMockPythFeed(
                addAssetData.pythId, startPrice, startConf, startExpo, startEmaPrice, startEmaConf, startPublishTime
            );
    }

    function addSpoke(uint16 chainId, address wormholeAddress, address tokenBridgeAddress) internal {
        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(wormholeAddress, getHubData().guardianSigner);
        IWormhole wormholeContract = wormholeSimulator.wormhole();
        ITokenBridge tokenBridgeContract = ITokenBridge(tokenBridgeAddress);


        Spoke spoke = new Spoke(chainId, wormholeAddress, tokenBridgeAddress, getHubData().hubChainId, address(getHub()));
        SpokeData memory spokeData = SpokeData({
            foreignTokenBridgeAddress: bytes32(uint256(uint160(tokenBridgeAddress))),
            foreignChainId: chainId,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            wormholeSimulator: wormholeSimulator,
            spoke: spoke
        });
        addSpokeData(spokeData);
    }   

    function setVm(Vm vm) internal {
        _testState.vm = vm;
    }

    function setPublishTime(uint64 publishTime) internal {
        _testState.publishTime = publishTime;
    }

    function setOracleMode(uint8 newOracleMode) internal {
        _testState.oracleMode = newOracleMode;
    }

    function setDebug(bool debug) internal {
        _testState.debug = debug;
    }

}
