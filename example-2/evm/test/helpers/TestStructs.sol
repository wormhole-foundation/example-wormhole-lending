// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";



import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestStructs {
    struct HubData {
        Hub hub;
        uint16 hubChainId;
        IWormhole wormholeContract;
        ITokenBridge tokenBridgeContract;
        uint256 guardianSigner;
        WormholeSimulator wormholeSimulator;
    }
    struct SpokeData {
        bytes32 foreignTokenBridgeAddress;
        uint16 foreignChainId;
        IWormhole wormholeContract;
        ITokenBridge tokenBridgeContract;
        WormholeSimulator wormholeSimulator;
        Spoke spoke;
    }
    struct Asset {
        address assetAddress;
        IERC20 asset;
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        uint8 decimals;
        uint256 reserveFactor;
        bytes32 pythId;
    }
}
