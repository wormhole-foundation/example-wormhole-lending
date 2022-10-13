// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./HubStructs.sol";

contract HubEvents {}

contract HubStorage {
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

        // allowlist for spoke contracts
        mapping(uint16 => address) spokeContracts;

        // address => AssetInfo
        mapping(address => HubStructs.AssetInfo) assetInfos;

        // vault for lending
        mapping(address => mapping(address => HubStructs.VaultAmount)) vault;

        // total asset amounts (tokenAddress => (uint256, uint256))
        mapping(address => HubStructs.VaultAmount) totalAssets;

        // interest accrual indices
        mapping(address => HubStructs.AccrualIndices) indices;

        // wormhole message hashes
        mapping(bytes32 => bool) consumedMessages;

        // last timestamp for update
        mapping(address => uint256) lastActivityBlockTimestamps;

        // interest rate models
        mapping(address => HubStructs.InterestRateModel) interestRateModels;
        
        // interest accrual rate precision level
        uint256 interestAccrualIndexPrecision;

        // storage gap
        uint256[50] ______gap;
    }
}

contract HubState {
    HubStorage.State _state;
}