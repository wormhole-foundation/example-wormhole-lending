// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IMockPyth.sol";
import "../HubSpokeStructs.sol";
import "./HubState.sol";

import "forge-std/console.sol";

contract HubGetters is Context, HubSpokeStructs, HubState {

    function getChainId() internal view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function tokenBridge() internal view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.provider.tokenBridge));
    }

    function tokenBridgeAddress() internal view returns (address) {
        return _state.provider.tokenBridge;
    }

    function consistencyLevel() internal view returns (uint8) {
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

    function getInterestRateModel(address assetAddress) internal view returns (PiecewiseInterestRateModel memory) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);
        return assetInfo.interestRateModel;
    }

    function getInterestAccrualIndices(address assetAddress) public view returns (AccrualIndices memory) {
        return _state.indices[assetAddress];
    }

    function getInterestAccrualIndexPrecision() public view returns (uint256) {
        return _state.interestAccrualIndexPrecision;
    }

    function getMaxDecimals() internal view returns (uint8) {
        return _state.MAX_DECIMALS;
    }

    function getVaultAmounts(address vaultOwner, address assetAddress) internal view returns (VaultAmount memory) {
        return _state.vault[vaultOwner][assetAddress];
    }

    function getGlobalAmounts(address assetAddress) internal view returns (VaultAmount memory) {
        return _state.totalAssets[assetAddress];
    }

    function getMaxLiquidationPortion() internal view returns (uint256) {
        return _state.maxLiquidationPortion;
    }

    function getMaxLiquidationPortionPrecision() internal view returns (uint256) {
        return _state.maxLiquidationPortionPrecision;
    }

    function getOracleMode() internal view returns (uint8) {
        return _state.oracleMode;
    }

    function getPythPriceStruct(bytes32 pythId) internal view returns (PythStructs.Price memory) {
        return _state.provider.pyth.getPrice(pythId);
    }

    function getOraclePrice(bytes32 oracleId) internal view returns (Price memory price) {
        return _state.oracle[oracleId];
    }

    function getMockPythPriceStruct(bytes32 pythId) internal view returns (PythStructs.Price memory) {
        return _state.provider.mockPyth.getPrice(pythId);
    }

    function getPriceStandardDeviationsPrecision() internal view returns (uint64) {
        return _state.priceStandardDeviationsPrecision;
    }

    function getPriceStandardDeviations() internal view returns (uint64) {
        return _state.priceStandardDeviations;
    }
}
