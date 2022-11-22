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

    function getAssetIndex(address assetAddress) internal view returns (uint) {
        for(uint i=0; i<_testState.assets.length; i++) {
            if(getAssetAddress(i) == assetAddress) {
                return i;
            }
        }
        return 2**32;
    }

    function getActionStateData(address vault, address assetAddress, bool isNative) internal view returns(ActionStateData memory data) {
        uint256 balanceUser;
        if(isNative) {
            balanceUser = address(vault).balance;
        } else {
            balanceUser = IERC20(assetAddress).balanceOf(vault);
        }

        VaultAmount memory vaultBalance =  getHub().getUserBalance(vault, assetAddress);

        data = ActionStateData({
            global: getHub().getGlobalBalance(assetAddress),
            vault: vaultBalance,
            balanceHub: IERC20(assetAddress).balanceOf(address(getHub())),
            balanceUser: balanceUser
        });
        
        if(getDebug()) {
            console.log("Balance of asset %s is (deposited: %s, borrowed: %s)", getAssetIndex(assetAddress), vaultBalance.deposited, vaultBalance.borrowed);
        }
    }

    

    function requireActionDataValid(Action action, address assetAddress, uint256 assetAmount, ActionStateData memory beforeData, ActionStateData memory afterData, bool paymentReversion) internal view {

        if(action == Action.Deposit) {
            require(areSame(beforeData.global.deposited + assetAmount, afterData.global.deposited, getDust(assetAddress, true)), "Did not deposit globally");
            require(areSame(beforeData.vault.deposited + assetAmount, afterData.vault.deposited, getDust(assetAddress, true)), "Did not deposit in vault");
            require(beforeData.balanceHub + assetAmount == afterData.balanceHub, "Did not transfer money to hub");
            require(beforeData.balanceUser == assetAmount + afterData.balanceUser, "Did not transfer money from user");
        } else if(action == Action.Repay) {
            uint256 amountRepayed = assetAmount;
            if(assetAmount >= beforeData.vault.borrowed) {
                amountRepayed = beforeData.vault.borrowed;
            }
            if(paymentReversion){
                require(beforeData.global.borrowed == afterData.global.borrowed, "Repay should not have gone through, so expect no changes to global borrowed");
                require(beforeData.vault.borrowed == afterData.vault.borrowed, "Repay should not have gone through, so expect no changes to vault borrowed");
                require(beforeData.balanceHub == afterData.balanceHub, "Token transfer should have been reverted, so expect no change to hub balance");
                require(beforeData.balanceUser == afterData.balanceUser, "Did transfer money from user, when should have reverted");
            }
            else {
                require(areSame(amountRepayed + afterData.global.borrowed, beforeData.global.borrowed, getDust(assetAddress, false)), "Did not repay globally");
                require(areSame(amountRepayed + afterData.vault.borrowed, beforeData.vault.borrowed, getDust(assetAddress, false)), "Did not repay in vault");
                require(beforeData.balanceHub + assetAmount == afterData.balanceHub, "Did not transfer money to hub");
                require(beforeData.balanceUser == assetAmount + afterData.balanceUser, "Did not transfer money from user");
            }
            
        } else if(action == Action.Withdraw) {
            require(areSame(beforeData.global.deposited, assetAmount  + afterData.global.deposited, getDust(assetAddress, true)), "Did not borrow globally");
            require(areSame(beforeData.vault.deposited, assetAmount + afterData.vault.deposited, getDust(assetAddress, true)), "Did not borrow from vault");
            require(beforeData.balanceHub == assetAmount + afterData.balanceHub, "Did not transfer money from hub");
            require(beforeData.balanceUser + assetAmount == afterData.balanceUser, "Did not transfer money to user");
        } else if(action == Action.Borrow) {
            require(areSame(afterData.global.borrowed, beforeData.global.borrowed + assetAmount, getDust(assetAddress, false)), "Did not withdraw globally");
            require(areSame(afterData.vault.borrowed, beforeData.vault.borrowed + assetAmount, getDust(assetAddress, false)), "Did not withdraw from vault");
            require(beforeData.balanceHub == assetAmount + afterData.balanceHub, "Did not transfer money from hub");
            require(beforeData.balanceUser + assetAmount == afterData.balanceUser, "Did not transfer money to user");
        }
    }

    function areSame(uint256 a, uint256 b, uint256 dust) internal pure returns (bool) {
        return a >= b && (a < b + dust);
    }

    function getDust(address assetAddress, bool depositedOrBorrowed) internal view returns (uint256) {
        if(depositedOrBorrowed) {
            return getHub().getInterestAccrualIndices(assetAddress).deposited/getHub().getInterestAccrualIndexPrecision() + 1;
        }
        return getHub().getInterestAccrualIndices(assetAddress).borrowed/getHub().getInterestAccrualIndexPrecision() + 1;
    }

    
}
