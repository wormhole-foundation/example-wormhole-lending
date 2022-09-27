// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct NormalizedAmounts {
    uint256 deposited;
    uint256 borrowed;
}

struct MessageHeader {
    address borrower;
    // collateral info
    address collateralAddress; // for verification
    // borrow info
    address borrowAddress; // for verification
}

struct BorrowMessage {
    MessageHeader header;
    uint256 borrowAmount;
}

struct RepayMessage {
    MessageHeader header;
    uint256 repayAmount;
}

struct LiquidationIntentMessage {
    MessageHeader header;
}

struct RevertBorrowMessage {
    MessageHeader header;
    uint256 borrowAmount;
}

struct InterestRateModel {
    uint64 ratePrecision;
    uint64 rateIntercept;
    uint64 rateCoefficientA;
    // TODO: add more complexity for example?
}
