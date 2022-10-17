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
        uint256 collateralizationRatio;
        uint256 reserveFactor;
        bytes32 pythId;
        // pyth id info
        uint8 decimals;
        bool exists;
    }

    struct InterestRateModel {
        uint64 ratePrecision;
        uint64 rateIntercept;
        uint64 rateCoefficientA;
        // TODO: add more complexity for example?
        uint64 reserveFactor;
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
        uint256 collateralizationRatio;
        uint256 reserveFactor;
        bytes32 pythId;
        uint8 decimals;
    }

}
