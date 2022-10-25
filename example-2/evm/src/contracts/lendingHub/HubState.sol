// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./HubStructs.sol";

contract HubEvents {}

contract HubStorage is HubStructs {
    struct Provider {
        uint16 chainId;
        address payable wormhole;
        address tokenBridge;
        address pyth;
    }

    struct State {
        Provider provider;
        
        // contract deployer
        address owner;

        // number of confirmations for wormhole messages
        uint8 consistencyLevel;

        // allowlist for tokens
        address[] allowList;

        // mock Pyth address
        address mockPythAddress;

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
        mapping(address => InterestRateModel) interestRateModels;
        
        // interest accrual rate precision level
        uint256 interestAccrualIndexPrecision;

        // collateralization ratio precision
        uint256 collateralizationRatioPrecision;

        // maximum decimals out of assets
        uint8 MAX_DECIMALS;

        // storage gap
        uint256[50] ______gap;

        // MockOracle (TODO: remove if we get oracle contract up and running)
        mapping(bytes32 => Price) oracle;
    }
}

contract HubState {
    HubStorage.State _state;
}