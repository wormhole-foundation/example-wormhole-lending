// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./CrossChainBorrowLendStructs.sol";

contract CrossChainBorrowLendStorage {
    struct State {
        // wormhole things
        address wormholeContractAddress;
        uint8 consistencyLevel;
        uint16 targetChainId;
        // precision variables
        uint256 collateralizationRatioPrecision;
        uint256 interestRatePrecision;
        // mock pyth price oracle
        address mockPythAddress;
        bytes32 targetContractAddress;
        // borrow and lend activity
        address collateralAssetAddress;
        bytes32 collateralAssetPythId;
        uint256 collateralizationRatio;
        address borrowingAssetAddress;
        SourceTargetUints interestAccrualIndex;
        uint256 interestAccrualIndexPrecision;
        uint256 lastActivityBlockTimestamp;
        SourceTargetUints totalAssets;
        uint256 repayGracePeriod;
        mapping(address => SourceTargetUints) accountAssets;
        bytes32 borrowingAssetPythId;
        mapping(bytes32 => bool) consumedMessages;
        InterestRateModel interestRateModel;
    }
}

contract CrossChainBorrowLendState {
    CrossChainBorrowLendStorage.State state;
}
