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

    function consistencyLevel() internal view returns (uint8) {
        return _state.consistencyLevel;
    }

    function getAllowList() internal view returns (address[] memory) {
        return _state.allowList;
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

    function getAssetInfo(address assetAddress) internal view returns (AssetInfo memory) {
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

    function getVaultAmounts(address vaultOwner, address assetAddress) internal view returns (VaultAmount memory) {
        return _state.vault[vaultOwner][assetAddress];
    } 

    function getGlobalAmounts(address assetAddress) internal view returns (VaultAmount memory) {
        return _state.totalAssets[assetAddress];
    }

    function normalizeAmount(uint256 denormalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (denormalizedAmount * _state.interestAccrualIndexPrecision) / interestAccrualIndex;
    }

    function denormalizeAmount(uint256 normalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (normalizedAmount * interestAccrualIndex) / _state.interestAccrualIndexPrecision;
    }

    function denormalizeVaultAmount(VaultAmount memory va, address assetAddress) internal view returns (VaultAmount memory) {
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);
        uint256 denormalizedDeposited = denormalizeAmount(va.deposited, indices.deposited);
        uint256 denormalizedBorrowed = denormalizeAmount(va.borrowed, indices.borrowed);
        return VaultAmount({
            deposited: denormalizedDeposited,
            borrowed: denormalizedBorrowed
        });

    }

    function getOraclePrices(address assetAddress) internal view returns (uint64) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        IMockPyth.PriceFeed memory feed = mockPyth().queryPriceFeed(assetInfo.pythId);

        // sanity check the price feeds
        require(feed.price.price > 0, "negative prices detected");

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return uint64(feed.price.price);
    }

    function getVaultEffectiveNotionalValue(address vaultOwner) internal view returns (uint256) {
        uint256 effectiveNotionalDeposited = 0;
        uint256 effectiveNotionalBorrowed = 0;

        address[] memory allowList = getAllowList();

        for(uint i=0; i<allowList.length; i++) {
            address asset = allowList[i];

            VaultAmount memory normalizedAmounts = getVaultAmounts(vaultOwner, asset);

            uint64 price = getOraclePrices(asset);
            
            AssetInfo memory assetInfo = getAssetInfo(asset);

            AccrualIndices memory indices = getInterestAccrualIndices(asset);
            
            uint256 denormalizedDeposited = denormalizeAmount(normalizedAmounts.deposited, indices.deposited);
            uint256 denormalizedBorrowed = denormalizeAmount(normalizedAmounts.borrowed, indices.borrowed);

            effectiveNotionalDeposited += denormalizedDeposited * price / (10**assetInfo.decimals);
            effectiveNotionalBorrowed += denormalizedBorrowed * assetInfo.collateralizationRatio * price / (10**assetInfo.decimals) / getCollateralizationRatioPrecision();
        }  

        return effectiveNotionalDeposited - effectiveNotionalBorrowed;
    }

    function getCollateralizationRatioPrecision() internal view returns (uint256) {
        return _state.collateralizationRatioPrecision;
    }


    // TODO: cycle through all assets in the vault
    function allowedToWithdraw(address vaultOwner, address assetAddress, uint256 assetAmount) internal view returns (bool) {       

        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint64 price = getOraclePrices(assetAddress);

        uint256 vaultValue = getVaultEffectiveNotionalValue(vaultOwner); 

        VaultAmount memory amounts = denormalizeVaultAmount(getVaultAmounts(vaultOwner, assetAddress), assetAddress);

        return (amounts.deposited - amounts.borrowed >= assetAmount) && (vaultValue >= assetAmount * price / (10**assetInfo.decimals));
    }

    function allowedToBorrow(address vaultOwner, address assetAddress, uint256 assetAmount) internal view returns (bool) {       
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint64 price = getOraclePrices(assetAddress);

        uint256 vaultValue = getVaultEffectiveNotionalValue(vaultOwner); 

        VaultAmount memory globalAmounts = denormalizeVaultAmount(getGlobalAmounts(assetAddress), assetAddress);

        return (globalAmounts.deposited - globalAmounts.borrowed >= assetAmount) && (vaultValue >= assetAmount * price * assetInfo.collateralizationRatio / (10**assetInfo.decimals));
    }

    function allowedToLiquidate(address vault, address[] memory assetRepayAddresses, address[] memory assetRepayAmounts, uint64[] memory pricesRepay, address[] memory assetReceiptAddresses, uint256[] memory assetReceiptAmounts, uint64[] memory pricesReceipt) internal view returns (bool) {
        bool underwater = checkUnderwater(vault);



        // TODO: return underwater && bool of whether repay amount valid
    }

    function checkUnderwater(address vault) internal view returns (bool){
        address[] memory allowList = getAllowList();
        uint256 effectiveNotionalDeposited = 0;
        uint256 effectiveNotionalBorrowed = 0;

        for(uint i=0; i<allowList.length; i++){
            address assetAddress = allowList[i];

            VaultAmount memory vaultAmount = getVaultAmounts(vault, assetAddress);
            AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);
            AssetInfo memory assetInfo = getAssetInfo(assetAddress);
            uint64 price = getOraclePrices(assetAddress);

            effectiveNotionalDeposited += denormalizeAmount(vaultAmount.deposited, indices.deposited) * price / (10**assetInfo.decimals);
            effectiveNotionalBorrowed += denormalizeAmount(vaultAmount.borrowed, indices.borrowed) * assetInfo.collateralizationRatio * price / (10**assetInfo.decimals);
        }

        return (effectiveNotionalDeposited < effectiveNotionalBorrowed);
    }

    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(registered_info.exists, "Unregistered asset");
    }

    /*
    function checkValidAddresses(address[] calldata assetAddresses) internal view {
        mapping(address => bool) memory observedAssets;

        for(uint i=0; i<assetAddresses.length; i++){
            address assetAddress = assetAddresses[i];
            // check if asset address is allowed
            AssetInfo memory registered_info = getAssetInfo(assetAddress);
            require(registered_info.isValue, "Unregistered asset");

            // check if each address is unique
            // require(!observedAssets[assetAddress], "Repeated asset");

            // observedAssets[assetAddress] = true;
        }
    }*/
}