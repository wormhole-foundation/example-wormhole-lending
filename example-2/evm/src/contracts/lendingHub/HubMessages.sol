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
        header.payloadID = serialized.toUint8(index);
        index += 1;
        header.sender = serialized.toAddress(index);
    }

    function decodeDepositMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.DepositMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 1, "invalid message");
        index += 21;
        uint32 length = serialized.toUint32(index);
        index += 4;

        // parse the asset addresses
        address[] memory assetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            assetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetAddresses = assetAddresses;
        
        // parse the asset amounts
        uint256[] memory assetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            assetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetAmounts = assetAmounts;

        
        /*
        params.borrowAmount = serialized.toUint256(index += 32);
        params.totalNormalizedBorrowAmount = serialized.toUint256(index += 32);
        params.interestAccrualIndex = serialized.toUint256(index += 32);

        require(params.header.payloadID == 1, "invalid message");
        require(index == serialized.length, "index != serialized.length");
        require(assetAddresses.length == length, "Asset addresses length is incorrect");
        */

    }
    
    function decodeWithdrawMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.WithdrawMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 2, "invalid message");
        index += 21;
        uint32 length = serialized.toUint32(index);
        index += 4;

        // parse the asset addresses
        address[] memory assetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            assetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetAddresses = assetAddresses;
        
        // parse the asset amounts
        uint256[] memory assetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            assetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetAmounts = assetAmounts;
    }
    
    function decodeBorrowMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.BorrowMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 3, "invalid message");
        index += 21;
        uint32 length = serialized.toUint32(index);
        index += 4;

        // parse the asset addresses
        address[] memory assetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            assetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetAddresses = assetAddresses;
        
        // parse the asset amounts
        uint256[] memory assetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            assetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetAmounts = assetAmounts;
    }
    
    function decodeRepayMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.RepayMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 4, "invalid message");
        index += 21;
        uint32 length = serialized.toUint32(index);
        index += 4;

        // parse the asset addresses
        address[] memory assetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            assetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetAddresses = assetAddresses;
        
        // parse the asset amounts
        uint256[] memory assetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            assetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetAmounts = assetAmounts;
    }
    
    function decodeLiquidationMessage(bytes memory serialized)
        internal
        pure
        returns (HubStructs.LiquidationMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodeMessageHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 5, "invalid message");
        index += 21;
        
        // repay section of the message
        uint32 repayLength = serialized.toUint32(index);
        index += 4;

        // parse the repay asset addresses
        address[] memory repayAssetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            repayAssetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.repayAssetAddresses = repayAssetAddresses;
        
        // parse the repay asset amounts
        uint256[] memory repayAssetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            repayAssetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.repayAssetAmounts = repayAssetAmounts;
        
        
        // receipt section of the message
        uint32 receiptLength = serialized.toUint32(index);
        index += 4;

        // parse the receipt asset addresses
        address[] memory receiptAssetAddresses = new address[](length);
        for(uint i=0; i<n; i++){
            receiptAssetAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.receiptAssetAddresses = receiptAssetAddresses;
        
        // parse the receipt asset amounts
        uint256[] memory receiptAssetAmounts = new uint256[](length);
        for(uint i=0; i<n; i++){
            receiptAssetAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.receiptAssetAmounts = receiptAssetAmounts;
    }


}
