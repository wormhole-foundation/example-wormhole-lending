// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../libraries/external/BytesLib.sol";

import "./HubStructs.sol";

contract HubMessages {
    using BytesLib for bytes;

    function encodeMessageHeader(HubStructs.MessageHeader memory header)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                header.sender
            );
    }

    function encodeDepositMessage(HubStructs.DepositMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(1), // payloadID
                encodeMessageHeader(message.header),
                message.assetAddresses,
                message.assetAmounts
            );
    }

    function encodeWithdrawMessage(HubStructs.WithdrawMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(2), // payloadID
                encodeMessageHeader(message.header),
                message.assetAddresses.length,
                message.assetAddresses,
                message.assetAmounts
            );
    }

    function encodeBorrowMessage(HubStructs.BorrowMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(3), // payloadID
                encodeMessageHeader(message.header),
                message.assetAddresses.length,
                message.assetAddresses,
                message.assetAmounts
            );
    }

    function encodeRepayMessage(HubStructs.RepayMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(4), // payloadID
                encodeMessageHeader(message.header),
                message.assetAddresses.length,
                message.assetAddresses,
                message.assetAmounts
            );
    }

    function encodeLiquidationMessage(HubStructs.LiquidationMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(5), // payloadID
                encodeMessageHeader(message.header),
                message.vault,
                message.assetRepayAddresses.length,
                message.assetReceiptAddresses.length,
                message.assetRepayAddresses,
                message.assetRepayAmounts,
                message.assetReceiptAddresses,
                message.assetReceiptAmounts
            );
    }

    function decodeMessageHeader(bytes memory serialized)
        internal
        pure
        returns (HubStructs.MessageHeader memory header)
    {
        uint256 index = 0;

        // parse the header
        header.payloadID = serialized.toUint8(index += 1);
        header.sender = serialized.toAddress(index += 20);
    }

    function decodeDepositMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.DepositMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index += 21)
        );
        uint32 length = serialized.toUint32(index);
        index += 4;

        address[] memory assetAddresses = new address[](length);
        /*
        params.borrowAmount = serialized.toUint256(index += 32);
        params.totalNormalizedBorrowAmount = serialized.toUint256(index += 32);
        params.interestAccrualIndex = serialized.toUint256(index += 32);

        require(params.header.payloadID == 1, "invalid message");
        require(index == serialized.length, "index != serialized.length");
        require(assetAddresses.length == length, "Asset addresses length is incorrect");
        */

    }


}
