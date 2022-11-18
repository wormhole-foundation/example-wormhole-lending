// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract HubStorage is HubSpokeStructs {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        address tokenBridge;
        IPyth pyth;
        MockPyth mockPyth;
    }

    struct State {
        Provider provider;
        // number of confirmations for wormhole messages
        uint8 consistencyLevel;
        // allowlist for assets
        address[] allowList;
        // mock Pyth address
        address mockPythAddress;
        // oracle mode: 0 for Pyth, 1 for mock Pyth, 2 for fake oracle
        uint8 oracleMode;
        // max liquidation bonus
        uint256 maxLiquidationBonus;
        // allowlist for spoke contracts
        mapping(uint16 => address) spokeContracts;
        // address => AssetInfo
        mapping(address => AssetInfo) assetInfos;
        // vault for lending
        mapping(address => mapping(address => VaultAmount)) vault;
        // total asset amounts (tokenAddress => (uint256, uint256))
        mapping(address => VaultAmount) totalAssets;
        // interest accrual indices
        mapping(address => AccrualIndices) indices;
        // wormhole message hashes
        mapping(bytes32 => bool) consumedMessages;
        // last timestamp for update
        mapping(address => uint256) lastActivityBlockTimestamps;
        // interest rate models
        mapping(address => PiecewiseInterestRateModel) interestRateModels;
        // interest accrual rate precision level
        uint256 interestAccrualIndexPrecision;
        // collateralization ratio precision
        uint256 collateralizationRatioPrecision;
        // maximum decimals out of assets
        uint8 MAX_DECIMALS;
        // storage gap
        uint256[50] ______gap;
        // MockOracle
        mapping(bytes32 => Price) oracle;
        // max portion of debt liquidator is allowed to repay
        uint256 maxLiquidationPortion;
        // precision for maxLiquidationPortion
        uint256 maxLiquidationPortionPrecision;
        // number of standard deviations to shift for lower and upper bound prices
        uint64 priceStandardDeviations;
        // precision for priceStandardDeviations
        uint64 priceStandardDeviationsPrecision;
    }
}

contract HubState is Ownable {
    HubStorage.State _state;
}
