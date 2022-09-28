// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct NormalizedAmounts {
    uint256 deposited;
    uint256 borrowed;
}

struct MessageHeader {
    uint8 payloadID;
    // address of the borrower
    address borrower;
    // collateral info
    address collateralAddress; // for verification
    // borrow info
    address borrowAddress; // for verification
}

struct BorrowMessage {
    // payloadID = 1
    MessageHeader header;
    uint256 borrowAmount;
    uint256 totalNormalizedBorrowAmount;
}

struct RevertBorrowMessage {
    // payloadID = 2
    MessageHeader header;
    uint256 borrowAmount;
}

struct RepayMessage {
    // payloadID = 3
    MessageHeader header;
    uint256 repayAmount;
}

struct LiquidationIntentMessage {
    // payloadID = 4
    MessageHeader header;
}

struct InterestRateModel {
    uint64 ratePrecision;
    uint64 rateIntercept;
    uint64 rateCoefficientA;
    // TODO: add more complexity for example?
}
