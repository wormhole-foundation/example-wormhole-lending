// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../../interfaces/IMockPyth.sol";
import "./HubStructs.sol";
import "./HubState.sol";

import "forge-std/console.sol";

contract HubGetters is Context, HubStructs, HubState {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function getChainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormhole() public view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function tokenBridge() public view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.provider.tokenBridge));
    }

    function tokenBridgeAddress() public view returns (address) {
        return _state.provider.tokenBridge;
    }

    function setOracleMode() public view returns (uint8) {
        return _state.oracleMode;
    }

    function consistencyLevel() public view returns (uint8) {
        return _state.consistencyLevel;
    }

    function getAllowList() public view returns (address[] memory) {
        return _state.allowList;
    }

    function getMaxLiquidationBonus() public view returns (uint256) {
        return _state.maxLiquidationBonus;
    }

    function getCollateralizationRatioPrecision() public view returns (uint256) {
        return _state.collateralizationRatioPrecision;
    }

    function getSpokeContract(uint16 chainId) public view returns (address) {
        return _state.spokeContracts[chainId];
    }

    function mockPyth() public view returns (IMockPyth) {
        return IMockPyth(_state.mockPythAddress);
    }

    function messageHashConsumed(bytes32 vmHash) public view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getAssetInfo(address assetAddress) public view returns (AssetInfo memory) {
        return _state.assetInfos[assetAddress];
    }

    function getLastActivityBlockTimestamp(address assetAddress) public view returns (uint256) {
        return _state.lastActivityBlockTimestamps[assetAddress];
    }

    function getTotalAssetsDeposited(address assetAddress) public view returns (uint256) {
        return _state.totalAssets[assetAddress].deposited;
    }

    function getTotalAssetsBorrowed(address assetAddress) public view returns (uint256) {
        return _state.totalAssets[assetAddress].borrowed;
    }

    function getInterestRateModel(address assetAddress) public view returns (InterestRateModel memory) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);
        return assetInfo.interestRateModel;
    }

    function getInterestAccrualIndices(address assetAddress) public view returns (AccrualIndices memory) {
        return _state.indices[assetAddress];
    }

    function getInterestAccrualIndexPrecision() public view returns (uint256) {
        return _state.interestAccrualIndexPrecision;
    }

    function getMaxDecimals() public view returns (uint8) {
        return _state.MAX_DECIMALS;
    }

    function getVaultAmounts(address vaultOwner, address assetAddress) public view returns (VaultAmount memory) {
        return _state.vault[vaultOwner][assetAddress];
    } 

    function getGlobalAmounts(address assetAddress) public view returns (VaultAmount memory) {
        return _state.totalAssets[assetAddress];
    }

    function getMaxLiquidationPortion() public view returns (uint256) {
        return _state.maxLiquidationPortion;
    }

    function getMaxLiquidationPortionPrecision() public view returns (uint256) {
        return _state.maxLiquidationPortionPrecision;
    }

    function getOracleMode() public view returns (uint8) {
        return _state.oracleMode;
    }

    function getPythPriceStruct(bytes32 pythId) public view returns (PythStructs.Price memory) {
        return _state.provider.pyth.getPrice(pythId);
    }

    function getOraclePrice(bytes32 oracleId) public view returns (Price memory price) {
        return _state.oracle[oracleId];
    }

    function getMockPythPriceStruct(bytes32 pythId) public view returns (PythStructs.Price memory) {
        return _state.provider.mockPyth.getPrice(pythId);
    }

    function getNConf() public view returns (uint64, uint64) {
        return (_state.nConf, _state.nConfPrecision);
    }
}