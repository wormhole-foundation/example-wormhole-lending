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

    function normalizeAmount(uint256 denormalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (denormalizedAmount * _state.interestAccrualIndexPrecision) / interestAccrualIndex;
    }

    function denormalizeAmount(uint256 normalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (normalizedAmount * interestAccrualIndex) / _state.interestAccrualIndexPrecision;
    }

    function getOraclePrices(address assetAddress) internal view returns (uint64) {
        IMockPyth.PriceFeed memory feed = mockPyth().queryPriceFeed(assetAddress);

        // sanity check the price feeds
        require(feed.price.price > 0, "negative prices detected");

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return uint64(feed.price.price);
    }

    function allowedToWithdraw(address vaultOwner, address[] assetAddresses, address[] assetAmounts, uint64[] prices) internal view returns (bool) {       
        uint256 effectiveNotionalDeposited = 0;
        uint256 effectiveNotionalBorrowed = 0;

        for(uint i=0; i<assetAddresses.length; i++) {
            address assetAddress = assetAddresses[i];
            uint256 assetAmount = assetAmounts[i];
            uint256 assetPrice = prices[i];
            AssetInfo assetInfo = getAssetInfo(assetAddress);

            VaultAmount normalizedAmounts = getVaultAmounts(vaultOwner, assetAddress);

            AccrualIndices indices = getInterestAccrualIndices(params.assetAddresses[i]);
            
            uint256 denormalizedDeposited = denormalizeAmount(normalizedAmounts.deposited, indices.deposited);
            uint256 denormalizedBorrowed = denormalizeAmount(normalizedAmounts.borrowed, indices.borrowed);
                    
            effectiveNotionalDeposited += denormalizedDeposited * price / assetInfo.decimals;
            effectiveNotionalBorrowed += (denormalizedBorrowed + assetAmount) * assetInfo.collateralizationRatio * price / assetInfo.decimals;
        }       

        return (effectiveNotionalDeposited >= effectiveNotionalBorrowed);
    }

    function checkValidAddresses(address[] assetAddresses) {
        mapping(address => bool) observedAssets;

        for(uint i=0; i<assetAddresses.length; i++){
            address assetAddress = assetAddresses[i];
            // check if asset address is allowed
            AssetInfo registered_info = getAssetInfo(assetAddress);
            if (!registered_info.isValue){
                revert UnregisteredAsset(assetAddress);
            }

            // check if each address is unique
            if (observedAssets[assetAddress]){
                revert AlreadyObservedAsset(assetAddress);
            }

            observedAssets[assetAddress] = true;
        }
    }
}