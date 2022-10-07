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
    }

    struct MessageHeader {
        uint8 payloadID;
        // address of the sender
        address sender;
        // chain information
        uint16 chainId;
        // collateral info
    }

    struct RegisterSpokeMessage {
        // payloadId = 1
        MessageHeader header;
        address spokeContractAddress;
    }

    struct DepositMessage {
        // payloadId = 2
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct WithdrawMessage {
        // payloadId = 3
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct BorrowMessage {
        // payloadId = 4
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct RepayMessage {
        // payloadId = 5
        MessageHeader header;
        address[] assetAddresses;
        uint256[] assetAmounts;
    }

    struct LiquidationMessage {
        // payloadId = 6
        MessageHeader header;
        address vault; // address to liquidate
        address[] assetRepayAddresses;
        uint256[] assetRepayAmounts;
        address[] assetReceiptAddresses;
        uint256[] assetReceiptAmounts;
    }


}
