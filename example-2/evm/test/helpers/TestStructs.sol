// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {WormholeSimulator} from "./WormholeSimulator.sol";
import {HubSpokeStructs} from "../../src/contracts/HubSpokeStructs.sol";

contract TestStructs is HubSpokeStructs {
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
        uint64 ratePrecision;
        uint256[] kinks;
        uint256[] rates;
        uint256 reserveFactor;
        bytes32 pythId;
    }

    struct AddAsset {
        address assetAddress;
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        uint64 ratePrecision;
        uint256[] kinks;
        uint256[] rates;
        uint256 reserveFactor;
        bytes32 pythId;
    }

    struct RegisterChainMessage {
        bytes32 module;
        uint8 action;
        uint16 chainId;
        uint16 emitterChainId;
        bytes32 emitterAddress;
    }

    struct ActionParameters {
        Action action;
        uint256 spokeIndex;
        address assetAddress;
        uint256 assetAmount;
        bool expectRevert;
        string revertString;
        bool paymentReversion;
        bool prank;
        address prankAddress;
    }


    struct ActionStateData {
        VaultAmount global;
        VaultAmount vault;
        uint256 balanceHub;
        uint256 balanceUser;
    }

    struct LiquidationDataArrays {
            uint256[] userBalancePreRepay;
            uint256[] hubBalancePreRepay;
            uint256[] userBalancePostRepay;
            uint256[] hubBalancePostRepay;
            uint256[] userBalancePreReceipt;
            uint256[] hubBalancePreReceipt;
            uint256[] userBalancePostReceipt;
            uint256[] hubBalancePostReceipt;
            uint256[] vaultToLiquidateAmountRepayPre;
            uint256[] vaultToLiquidateAmountReceiptPre;
            uint256[] vaultToLiquidateAmountRepayPost;
            uint256[] vaultToLiquidateAmountReceiptPost;
            uint256[] globalAmountRepayPre;
            uint256[] globalAmountReceiptPre;
            uint256[] globalAmountRepayPost;
            uint256[] globalAmountReceiptPost;
    }

    
}
