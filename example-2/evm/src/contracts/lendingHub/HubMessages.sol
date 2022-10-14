// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../libraries/external/BytesLib.sol";

import "./HubStructs.sol";

contract HubMessages is HubStructs {
    using BytesLib for bytes;

    function encodePayloadHeader(PayloadHeader memory header)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                header.sender
            );
    }

    function encodeDepositPayload(DepositPayload memory payload)
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

    function encodeWithdrawPayload(WithdrawPayload memory payload)
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

    function encodeBorrowPayload(BorrowPayload memory payload)
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

    function encodeRepayPayload(RepayPayload memory payload)
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

    function encodeRegisterAssetMessage(RegisterAssetMessage memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(5), // payloadID
                encodePayloadHeader(message.header),
                message.assetAddress,
                message.collateralizationRatio,
                message.reserveFactor,
                message.pythId,
                message.decimals
            );
    }

    function decodePayloadHeader(bytes memory serialized)
        internal
        pure
        returns (PayloadHeader memory header)
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
        returns (DepositPayload memory params)
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
        returns (WithdrawPayload memory params)
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
        returns (BorrowPayload memory params)
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
        returns (RepayPayload memory params)
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
    
    function decodeRegisterAssetMessage(bytes memory serialized)
        internal
        pure
        returns (RegisterAssetMessage memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodePayloadHeader(
            serialized.slice(index, index + 21)
        );
        require(params.header.payloadID == 5, "invalid payload");
        index += 21;

        
        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;

        // parse the collateralization rato
        uint256 collateralizationRatio = serialized.toUint256(index);
        index += 32;

        params.collateralizationRatio = collateralizationRatio;

        // parse the reserve factor
        uint256 reserveFactor = serialized.toUint256(index);
        index += 32;

        params.reserveFactor = reserveFactor;

        // parse the Pyth Id
        // TODO: is this valid?? better way to do the conversion from bytes to bytes32
        bytes32 pythId = bytes32(serialized.toUint256(index)); //serialized[index:index+4];
        index += 4;

        params.pythId = pythId;

        // parse the decimals
        uint8 decimals = serialized.toUint8(index);
        index += 1;

        params.decimals = decimals;
    }
}

