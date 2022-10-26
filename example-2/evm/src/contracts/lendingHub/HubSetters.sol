// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./HubState.sol";
import "./HubStructs.sol";
import "./HubGetters.sol";

contract HubSetters is HubStructs, HubState, HubGetters {
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

    function registerAssetInfo(address assetAddress, AssetInfo memory info) internal {
        _state.assetInfos[assetAddress] = info;

        // TODO: Take the deposit and borrow indices as input
        // TODO: Take the interest rate model as input
        AccrualIndices memory accrualIndices;
        accrualIndices.deposited = 1*getInterestAccrualIndexPrecision();
        accrualIndices.borrowed = 1*getInterestAccrualIndexPrecision();
        accrualIndices.lastBlock = block.timestamp;

        setInterestAccrualIndices(assetAddress, accrualIndices);

        // set the max decimals to max of current max and new asset decimals
        uint8 currentMaxDecimals = getMaxDecimals();
        if(info.decimals > currentMaxDecimals) {
            setMaxDecimals(info.decimals);
        }
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

    function setInterestAccrualIndices(address assetAddress, AccrualIndices memory indices) internal {
        _state.indices[assetAddress] = indices;
    }

    function setInterestAccrualIndexPrecision(uint256 interestAccrualIndexPrecision) internal {
        _state.interestAccrualIndexPrecision = interestAccrualIndexPrecision;
    }

    function setCollateralizationRatioPrecision(uint256 collateralizationRatioPrecision) internal {
        _state.collateralizationRatioPrecision = collateralizationRatioPrecision;
    }

    function setMaxDecimals(uint8 maxDecimals) internal {
        _state.MAX_DECIMALS = maxDecimals;
    }

    function setMaxLiquidationBonus(uint256 maxLiquidationBonus) internal {
        _state.maxLiquidationBonus = maxLiquidationBonus;
    }

    function setVaultAmounts(address vaultOwner, address assetAddress, VaultAmount memory vaultAmount) internal {
        _state.vault[vaultOwner][assetAddress] = vaultAmount;
    } 

    function setGlobalAmounts(address assetAddress, VaultAmount memory vaultAmount) internal {
        _state.totalAssets[assetAddress] = vaultAmount;
    }

    // setting oracle price (TODO: remove if we get oracle contract up and running)
    function setOraclePrice(bytes32 oracleId, Price memory price) public {
        _state.oracle[oracleId] = price;
    }
}