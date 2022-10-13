// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../libraries/external/BytesLib.sol";

import "./HubStructs.sol";

contract HubMessages {
    using BytesLib for bytes;

    function encodePayloadHeader(HubStructs.PayloadHeader memory header)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                header.sender
            );
    }

    function encodeDepositPayload(HubStructs.DepositPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(1), // payloadID
                encodePayloadHeader(payload.header),
                payload.assetAddress,
                payload.assetAmount
            );
    }

    function encodeWithdrawPayload(HubStructs.WithdrawPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(2), // payloadID
                encodePayloadHeader(payload.header),
                payload.assetAddress,
                payload.assetAmount
            );
    }

    function encodeBorrowPayload(HubStructs.BorrowPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(3), // payloadID
                encodePayloadHeader(payload.header),
                payload.assetAddress,
                payload.assetAmount
            );
    }

    function encodeRepayPayload(HubStructs.RepayPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(4), // payloadID
                encodePayloadHeader(payload.header),
                payload.assetAddress,
                payload.assetAmount
            );
    }

    /*
    function encodeLiquidationPayload(HubStructs.LiquidationPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(5), // payloadID
                encodePayloadHeader(payload.header),
                payload.vault,
                payload.assetRepayAddresses.length,
                payload.assetRepayAddresses,
                payload.assetRepayAmounts,
                payload.assetReceiptAddresses.length,
                payload.assetReceiptAddresses,
                payload.assetReceiptAmounts
            );
    }
    */

    function decodePayloadHeader(bytes memory serialized)
        internal
        pure
        returns (HubStructs.PayloadHeader memory header)
    {
        uint256 index = 0;

        // parse the header

        header.payloadID = serialized.toUint8(index);
        index += 1;
        header.sender = serialized.toAddress(index);

    }

    function decodeDepositPayload(bytes memory serialized)
        internal
        pure
        returns (HubStructs.DepositPayload memory params)
    {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 1, "invalid payload");
        index += 21;
       
        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;
        
        // parse the asset amount
        uint256 assetAmount = serialized.toUint256(index);
        index += 32;
        
        params.assetAmount = assetAmount;
    }

    
    function decodeWithdrawPayload(bytes memory serialized)
        internal
        pure
        returns (HubStructs.WithdrawPayload memory params)
    {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 2, "invalid payload");
        index += 21;
       

        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;
        
        // parse the asset amount
        uint256 assetAmount = serialized.toUint256(index);
        index += 32;
        
        params.assetAmount = assetAmount;
    }
    
    function decodeBorrowPayload(bytes memory serialized)
        internal
        pure
        returns (HubStructs.BorrowPayload memory params)
    {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 3, "invalid payload");
        index += 21;
       

        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;
        
        // parse the asset amount
        uint256 assetAmount = serialized.toUint256(index);
        index += 32;
        
        params.assetAmount = assetAmount;
    }
    
    function decodeRepayPayload(bytes memory serialized)
        internal
        pure
        returns (HubStructs.RepayPayload memory params)
    {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 4, "invalid payload");
        index += 21;
        

        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;
        
        // parse the asset amount
        uint256 assetAmount = serialized.toUint256(index);
        index += 32;
        
        params.assetAmount = assetAmount;
    }
    

    function decodeLiquidationPayload(bytes memory serialized)
        internal
        pure
        returns (HubStructs.LiquidationPayload memory params)
    {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 5, "invalid payload");
        index += 21;
        
        // repay section of the payload
        uint32 repayLength = serialized.toUint32(index);
        index += 4;

        // parse the repay asset addresses
        address[] memory assetRepayAddresses = new address[](repayLength);
        for(uint i=0; i<repayLength; i++){
            assetRepayAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetRepayAddresses = assetRepayAddresses;
        
        // parse the repay asset amounts
        uint256[] memory assetRepayAmounts = new uint256[](repayLength);
        for(uint i=0; i<repayLength; i++){
            assetRepayAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetRepayAmounts = assetRepayAmounts;
        
        
        // receipt section of the payload
        uint32 receiptLength = serialized.toUint32(index);
        index += 4;

        // parse the receipt asset addresses
        address[] memory assetReceiptAddresses = new address[](receiptLength);
        for(uint i=0; i<receiptLength; i++){
            assetReceiptAddresses[i] = serialized.toAddress(index);
            index += 20;
        }
        params.assetReceiptAddresses = assetReceiptAddresses;
        
        // parse the receipt asset amounts
        uint256[] memory assetReceiptAmounts = new uint256[](receiptLength);
        for(uint i=0; i<receiptLength; i++){
            assetReceiptAmounts[i] = serialized.toUint256(index);
            index += 32;
        }
        params.assetReceiptAmounts = assetReceiptAmounts;
    }


}
