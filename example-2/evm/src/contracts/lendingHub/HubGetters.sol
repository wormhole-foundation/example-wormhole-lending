// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";

import "./HubState.sol";

contract HubGetters is HubState, Context {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function tokenBridge() public view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.provider.tokenBridge));
    }

    function consistencyLevel() internal view returns (uint8) {
        return _state.consistencyLevel;
    }

    function getSpokeContract(uint16 chainId) internal view returns (address) {
        return _state.spokeContracts[chainId];
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getAssetInfo(address assetAddress) internal view returns (HubStructs.AssetInfo) {
        return _state.assetInfos[assetAddress];
    }

    function getLastActivityBlockTimestamp(address assetAddress) internal view returns (uint256) {
        return _state.lastActivityBlockTimestamps[assetAddress];
    }

    function getTotalAssetsDeposited(address assetAddress) internal view returns (uint256) {
        return _state.totalAssets[assetAddress].deposited;
    }

    function getTotalAssetsBorrowed(address assetAddress) internal view returns (uint256) {
        return _state.totalAssets[assetAddress].borrowed;
    }

    function getInterestRateModel(address assetAddress) internal view returns (InterestRateModel) {
        return _state.interestRateModels[assetAddress];
    }

    function getInterestAccrualIndices(address assetAddress) internal view returns (AccrualIndices) {
        return _state.indices[assetAddress];
    }

    function getVaultAmounts(address vaultOwner, address assetAddress) internal view returns (VaultAmount) {
        return _state.vault[vaultOwner][assetAddress];
    } 

    function getGlobalAmounts(address assetAddress) internal view returns (VaultAmount) {
        return _state.totalAssets[assetAddress];
    } 
}