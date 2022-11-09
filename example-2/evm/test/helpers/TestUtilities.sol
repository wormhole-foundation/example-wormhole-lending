// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";

import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestSetters} from "./TestSetters.sol";
import {TestGetters} from "./TestGetters.sol";


contract TestUtilities is TestStructs, TestState, TestGetters, TestSetters {

    
    function fetchSignedMessageFromSpokeLogs(uint256 spokeIndex, Vm.Log memory entry) internal returns (bytes memory) {
        return getSpokeData(spokeIndex).wormholeSimulator.fetchSignedMessageFromLogs(entry);
    }

    function fetchSignedMessageFromHubLogs(Vm.Log memory entry) internal returns (bytes memory) {
        return getHubData().wormholeSimulator.fetchSignedMessageFromLogs(entry);
    }

    function getSignedWHMsg(bytes memory message)
        internal
        returns (bytes memory encodedVM)
    {
        // get hash for signature
        bytes32 messageHash = keccak256(abi.encodePacked(keccak256(message)));

        // Sign the hash with the devnet guardian private key
        IWormhole.Signature[] memory sigs = new IWormhole.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = getVm().sign(getHubData().guardianSigner, messageHash);
        sigs[0].guardianIndex = 0;

        encodedVM = abi.encodePacked(
            uint8(1), // version
            getHubData().wormholeContract.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            message
        );
    }

    function registerChainOnHub(uint16 emitterChainId, bytes32 emitterAddress) internal {
        RegisterChainMessage memory registerMsg = RegisterChainMessage({
            module: 0x000000000000000000000000000000000000000000546f6b656e427269646765,
            action: 1, 
            chainId: 0,
            emitterChainId: emitterChainId,
            emitterAddress: emitterAddress
        });

        bytes memory payload = abi.encodePacked(
            uint32(0),
            uint32(0),
            uint16(1),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000004), // this should be the spoke address
            uint64(1),
            uint8(15),
            abi.encodePacked(registerMsg.module, registerMsg.action, registerMsg.chainId, registerMsg.emitterChainId, registerMsg.emitterAddress)
        );

        bytes memory registerChainSignedMsg = getSignedWHMsg(payload);

        getHubData().tokenBridgeContract.registerChain(registerChainSignedMsg);
        
    }

    function getActionStateData(address vault, address assetAddress, bool isNative) internal view returns(ActionStateData memory data) {
        uint256 balanceUser;
        if(isNative) {
            balanceUser = address(vault).balance;
        } else {
            balanceUser = IERC20(assetAddress).balanceOf(vault);
        }
        data = ActionStateData({
            global: getHub().getGlobalAmounts(assetAddress),
            vault: getHub().getVaultAmounts(vault, assetAddress),
            balanceHub: IERC20(assetAddress).balanceOf(address(getHub())),
            balanceUser: balanceUser
        });
    }

    function requireActionDataValid(Action action, address assetAddress, uint256 assetAmount, ActionStateData memory beforeData, ActionStateData memory afterData, bool paymentReversion) internal view {

        uint256 normalizedAssetAmountDeposited = getHub().normalizeAmount(assetAmount, getHub().getInterestAccrualIndices(assetAddress).deposited);
        uint256 normalizedAssetAmountBorrowed = getHub().normalizeAmount(assetAmount, getHub().getInterestAccrualIndices(assetAddress).borrowed);


        if(action == Action.Deposit) {
            require(beforeData.global.deposited + normalizedAssetAmountDeposited == afterData.global.deposited, "Did not deposit globally");
            require(beforeData.vault.deposited + normalizedAssetAmountDeposited == afterData.vault.deposited, "Did not deposit in vault");
            require(beforeData.balanceHub + assetAmount == afterData.balanceHub, "Did not transfer money to hub");
            require(beforeData.balanceUser - assetAmount == afterData.balanceUser, "Did not transfer money from user");
        } else if(action == Action.Repay) {

            if(paymentReversion){
                require(beforeData.global.borrowed == afterData.global.borrowed, "Repay should not have gone through, so expect no changes to global borrowed");
                require(beforeData.vault.borrowed == afterData.vault.borrowed, "Repay should not have gone through, so expect no changes to vault borrowed");
                require(beforeData.balanceHub == afterData.balanceHub, "Token transfer should have been reverted, so expect no change to hub balance");
            }
            else {
                require(beforeData.global.borrowed - normalizedAssetAmountBorrowed == afterData.global.borrowed, "Did not repay globally");
                require(beforeData.vault.borrowed - normalizedAssetAmountBorrowed == afterData.vault.borrowed, "Did not repay in vault");
                require(beforeData.balanceHub + assetAmount == afterData.balanceHub, "Did not transfer money to hub");
            }
            require(beforeData.balanceUser - assetAmount == afterData.balanceUser, "Did not transfer money from user");
        } else if(action == Action.Withdraw) {
            require(beforeData.global.deposited - normalizedAssetAmountDeposited  == afterData.global.deposited, "Did not borrow globally");
            require(beforeData.vault.deposited - normalizedAssetAmountDeposited  == afterData.vault.deposited, "Did not borrow from vault");
            require(beforeData.balanceHub - assetAmount == afterData.balanceHub, "Did not transfer money from hub");
            require(beforeData.balanceUser + assetAmount == afterData.balanceUser, "Did not transfer money to user");
        } else if(action == Action.Borrow) {
            require(beforeData.global.borrowed + normalizedAssetAmountBorrowed == afterData.global.borrowed, "Did not withdraw globally");
            require(beforeData.vault.borrowed + normalizedAssetAmountBorrowed == afterData.vault.borrowed, "Did not withdraw from vault");
            require(beforeData.balanceHub - assetAmount == afterData.balanceHub, "Did not transfer money from hub");
            require(beforeData.balanceUser + assetAmount == afterData.balanceUser, "Did not transfer money to user");
        }
    }
}
