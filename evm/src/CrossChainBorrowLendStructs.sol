// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct DepositedBorrowedUints {
    uint256 deposited;
    uint256 borrowed;
}

struct NormalizedTotalAmounts {
    uint256 deposited;
    uint256 borrowed;
}

struct NormalizedAmounts {
    uint256 sourceDeposited;
    uint256 sourceBorrowed;
    uint256 targetDeposited;
    uint256 targetBorrowed;
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
    uint256 interestAccrualIndex;
}

struct RevertBorrowMessage {
    // payloadID = 2
    MessageHeader header;
    uint256 borrowAmount;
    uint256 sourceInterestAccrualIndex;
}

struct RepayMessage {
    // payloadID = 3
    MessageHeader header;
    uint256 repayAmount;
    uint256 targetInterestAccrualIndex;
    uint256 repayTimestamp;
    uint8 paidInFull;
}

struct LiquidationIntentMessage {
    // payloadID = 4
    MessageHeader header;
    // TODO: add necessary variables
}

struct InterestRateModel {
    uint64 ratePrecision;
    uint64 rateIntercept;
    uint64 rateCoefficientA;
    // TODO: add more complexity for example?
}
