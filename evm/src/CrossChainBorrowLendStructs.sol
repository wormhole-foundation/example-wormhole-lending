// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct AssetAmounts {
    uint256 depositedAmount;
    uint256 borrowedAmount;
}

struct BorrowWormholePayload {
    address borrower;
    // collateral info
    address collateralAddress; // for verification
    uint256 collateralAmount;
    // borrow info
    address borrowAddress; // for verification
    uint256 borrowAmount;
}

struct InterestRateParameters {
    uint64 ratePrecision;
    uint64 linearRateCoefficientA;
    // TODO: add more complexity for example?
}
