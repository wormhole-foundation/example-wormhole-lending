// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract HubStructs {
    struct VaultAmount {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AccrualIndices {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastBlock;
    }

    struct AssetInfo {
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        bytes32 pythId;
        // pyth id info
        uint8 decimals;
        InterestRateModel interestRateModel;
        bool exists;
    }

    struct InterestRateModel {
        uint64 ratePrecision;
        uint64 rateIntercept;
        uint64 rateCoefficientA;
        // TODO: add more complexity for example?
        uint256 reserveFactor;
        uint256 reservePrecision;
    }




    struct PayloadHeader {
        uint8 payloadID;
        // address of the sender
        address sender;
        
    }

    struct DepositPayload {
        // payloadId = 1
        PayloadHeader header;
        address assetAddress;
        uint256 assetAmount;
    }

    struct WithdrawPayload {
        // payloadId = 2
        PayloadHeader header;
        address assetAddress;
        uint256 assetAmount;
    }

    struct BorrowPayload {
        // payloadId = 3
        PayloadHeader header;
        address assetAddress;
        uint256 assetAmount;
    }

    struct RepayPayload {
        // payloadId = 4
        PayloadHeader header;
        address assetAddress;
        uint256 assetAmount;
    }

    struct RegisterAssetPayload {
        // messageId = 5
        PayloadHeader header;
        address assetAddress;
        uint256 collateralizationRatioDeposit;
        uint256 collateralizationRatioBorrow;
        bytes32 pythId;
        uint64 ratePrecision;
        uint64 rateIntercept;
        uint64 rateCoefficientA;
        uint256 reserveFactor;
        uint256 reservePrecision;
        uint8 decimals;
    }

    // struct for mock oracle price
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }
}
