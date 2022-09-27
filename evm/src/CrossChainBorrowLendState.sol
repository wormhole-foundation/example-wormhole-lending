// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AssetAmounts} from "./CrossChainBorrowLendStructs.sol";

contract CrossChainBorrowLendStorage {
    struct State {
        address owner;
        // wormhole things
        address wormholeContractAddress;
        uint8 consistencyLevel;
        uint16 targetChainId;
        uint32 collateralizationRatioPrecision;
        uint256 interestRatePrecision = 1e18;
        // price oracle
        address priceOracleAddress;
        bytes32 targetContractAddress;
        // borrow and lend activity
        address collateralAssetAddress;
        uint256 collateralizationRatio;
        uint256 totalCollateralLiquidity;
        address borrowingAssetAddress;
        uint256 lastBorrowBlockTimestamp;
        mapping(address => AssetAmounts) accountAssets;
        mapping(bytes32 => bool) completedBorrows;
    }
}

contract CrossChainBorrowLendState {
    CrossChainBorrowLendStorage.State state;
}
