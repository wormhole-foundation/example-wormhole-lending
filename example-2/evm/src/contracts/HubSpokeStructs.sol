// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract HubSpokeStructs {
    struct VaultAmount {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AccrualIndices {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AssetInfo {
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        bytes32 pythId;
        // pyth id info
        uint8 decimals;
        PiecewiseInterestRateModel interestRateModel;
        bool exists;
    }

    struct InterestRateModel {
        uint64 ratePrecision;
        uint64 rateIntercept;
        uint64 rateCoefficientA;
        uint256 reserveFactor;
        uint256 reservePrecision;
    }

    struct PiecewiseInterestRateModel {
        uint64 ratePrecision;
        uint256[] kinks;
        uint256[] rates;
        uint256 reserveFactor;
        uint256 reservePrecision;
    }

    enum Action {
        Deposit,
        Borrow,
        Withdraw,
        Repay,
        DepositNative,
        RepayNative
    }

    enum Round {
        UP,
        DOWN
    }

    struct ActionPayload {
        Action action;
        address sender;
        address assetAddress;
        uint256 assetAmount;
    }

    // struct for mock oracle price
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }
}
