// SPDX-License-Identifier: UNLICENSED

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
