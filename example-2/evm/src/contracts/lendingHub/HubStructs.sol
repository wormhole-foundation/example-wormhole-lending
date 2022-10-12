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
        bool isValue;
    }

    struct InterestRateModel {
        uint64 ratePrecision;
        uint64 rateIntercept;
        uint64 rateCoefficientA;
        // TODO: add more complexity for example?
        uint64 reserveFactor;
    }




    struct MessageHeader {
        uint8 payloadID;
        // address of the sender
        address sender;
        
    }

    struct DepositMessage {
        // payloadId = 1
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct WithdrawMessage {
        // payloadId = 2
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct BorrowMessage {
        // payloadId = 3
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct RepayMessage {
        // payloadId = 4
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct LiquidationMessage {
        // payloadId = 5
        MessageHeader header;
        address vault; // address to liquidate
        address[] assetRepayAddresses;
        uint256[] assetRepayAmounts;
        address[] assetReceiptAddresses;
        uint256[] assetReceiptAmounts;
    }


}
