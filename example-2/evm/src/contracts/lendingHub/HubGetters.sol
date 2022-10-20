// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IMockPyth.sol";
import "./HubStructs.sol";
import "./HubState.sol";

contract HubGetters is Context, HubStructs, HubState {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function getChainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function tokenBridge() public view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.provider.tokenBridge));
    }

    // TODO: This is public for testing
    function consistencyLevel() public view returns (uint8) {
        return _state.consistencyLevel;
    }

    function getAllowList() internal view returns (address[] memory) {
        return _state.allowList;
    }

    function getMaxLiquidationBonus() internal view returns (uint256) {
        return _state.maxLiquidationBonus;
    }

    function getCollateralizationRatioPrecision() internal view returns (uint256) {
        return _state.collateralizationRatioPrecision;
    }

    function getSpokeContract(uint16 chainId) internal view returns (address) {
        return _state.spokeContracts[chainId];
    }

     function mockPyth() internal view returns (IMockPyth) {
        return IMockPyth(_state.mockPythAddress);
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getAssetInfo(address assetAddress) public view returns (AssetInfo memory) {
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

    function getInterestRateModel(address assetAddress) internal view returns (InterestRateModel memory) {
        return _state.interestRateModels[assetAddress];
    }

    function getInterestAccrualIndices(address assetAddress) internal view returns (AccrualIndices memory) {
        return _state.indices[assetAddress];
    }

    function getInterestAccrualIndexPrecision() internal view returns (uint256) {
        return _state.interestAccrualIndexPrecision;
    }

    // TODO: This is public for testing
    function getVaultAmounts(address vaultOwner, address assetAddress) public view returns (VaultAmount memory) {
        return _state.vault[vaultOwner][assetAddress];
    } 

    // TODO: This is public for testing
    function getGlobalAmounts(address assetAddress) public view returns (VaultAmount memory) {
        return _state.totalAssets[assetAddress];
    }

}