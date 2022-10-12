// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./HubState.sol";
import "./HubStructs.sol";

contract HubSetters is HubState {
    function setOwner(address owner) internal {
        _state.owner = owner;
    }

    function setChainId(uint16 chainId) internal {
        _state.provider.chainId = chainId;
    }

    function setWormhole(address wormholeAddress) internal {
        _state.provider.wormhole = payable(wormholeAddress);
    }

    function setTokenBridge(address tokenBridgeAddress) internal {
        _state.provider.tokenBridge = tokenBridgeAddress;
    }

    function setPyth(address pythAddress) internal {
        _state.provider.pyth = pythAddress;
    }

    function setConsistencyLevel(uint8 consistencyLevel) internal {
        _state.consistencyLevel = consistencyLevel;
    }

    function registerSpokeContract(uint16 chainId, address spokeContractAddress) internal {
        _state.spokeContracts[chainId] = spokeContractAddress;
    }

    function registerAssetInfo(address assetAddress, HubStructs.AssetInfo calldata info) internal {
        _state.assetInfos[assetAddress] = info;
    }

    function consumeMessageHash(bytes32 vmHash) internal {
        _state.consumedMessages[vmHash] = true;
    }

    function allowAsset(address assetAddress) internal {
        _state.allowList.push(assetAddress);
    }

    function setLastActivityBlockTimestamp(address assetAddress, uint256 blockTimestamp) internal {
        _state.lastActivityBlockTimestamps[assetAddress] = blockTimestamp;
    }

    function setInterestAccrualIndex(address assetAddress, HubStructs.AccrualIndices calldata indices) internal {
        _state.indices[assetAddress] = indices;
    }

    function setVaultAmounts(address vaultOwner, address assetAddress, HubStructs.VaultAmount calldata vaultAmount) internal {
        _state.vault[vaultOwner][assetAddress] = vaultAmount;
    } 

    function setGlobalAmounts(address assetAddress, HubStructs.VaultAmount calldata vaultAmount) internal {
        _state.totalAssets[assetAddress] = vaultAmount;
    } 
}