// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AssetAmounts, InterestRateParameters} from "./CrossChainBorrowLendStructs.sol";

contract CrossChainBorrowLendStorage {
    struct State {
        address owner;
        // wormhole things
        address wormholeContractAddress;
        uint8 consistencyLevel;
        uint16 targetChainId;
        uint32 collateralizationRatioPrecision;
        uint256 interestRatePrecision;
        // mock pyth price oracle
        address mockPythAddress;
        bytes32 targetContractAddress;
        // borrow and lend activity
        address collateralAssetAddress;
        bytes32 collateralAssetPythId;
        uint256 collateralizationRatio;
        //uint256 totalCollateralSupply;
        address borrowingAssetAddress;
        uint256 collateralPriceIndex;
        uint256 collateralPriceIndexPrecision;
        uint256 lastActivityBlockTimestamp;
        NormalizedAmounts totalAssets;
        mapping(address => NormalizedAmounts) accountAssets;
        bytes32 borrowingAssetPythId;
        mapping(bytes32 => bool) completedBorrows;
        InterestRateModel interestRateModel;
    }
}

contract CrossChainBorrowLendState {
    CrossChainBorrowLendStorage.State state;
}
