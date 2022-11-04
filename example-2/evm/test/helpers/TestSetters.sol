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

// TODO: add wormhole interface and use fork-url w/ mainnet

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

    function addAsset(address assetAddress, uint256 collateralizationRatioDeposit, uint256 collateralizationRatioBorrow, uint256 reserveFactor, bytes32 pythId) internal {
        (,bytes memory queriedDecimals) = assetAddress.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        Asset memory asset = Asset({
            assetAddress: assetAddress,
            asset: IERC20(assetAddress),
            collateralizationRatioDeposit: collateralizationRatioDeposit,
            collateralizationRatioBorrow: collateralizationRatioBorrow,
            decimals: decimals,
            reserveFactor: reserveFactor,
            pythId: pythId
        });
        addAsset(asset);
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

}
