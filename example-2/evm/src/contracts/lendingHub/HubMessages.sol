// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../libraries/external/BytesLib.sol";

import "./HubStructs.sol";

contract HubMessages is HubStructs {
    using BytesLib for bytes;

    function encodePayloadHeader(PayloadHeader memory header) internal pure returns (bytes memory) {
        return abi.encodePacked(header.sender);
    }

    function encodeDepositPayload(DepositPayload memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(1), // payloadID
            encodePayloadHeader(payload.header),
            payload.assetAddress,
            payload.assetAmount
        );
    }

    function encodeWithdrawPayload(WithdrawPayload memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(2), // payloadID
            encodePayloadHeader(payload.header),
            payload.assetAddress,
            payload.assetAmount
        );
    }

    function encodeBorrowPayload(BorrowPayload memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(3), // payloadID
            encodePayloadHeader(payload.header),
            payload.assetAddress,
            payload.assetAmount
        );
    }

    function encodeRepayPayload(RepayPayload memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(4), // payloadID
            encodePayloadHeader(payload.header),
            payload.assetAddress,
            payload.assetAmount
        );
    }

    function encodeRegisterAssetPayload(RegisterAssetPayload memory message)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                uint8(5), // payloadID
                encodePayloadHeader(message.header),
                message.assetAddress,
                message.collateralizationRatioDeposit,
                message.collateralizationRatioBorrow,
                message.pythId,
                message.ratePrecision,
                message.rateIntercept,
                message.rateCoefficientA,
                message.reserveFactor,
                message.reservePrecision,
                message.decimals
            );
    }

    function decodePayloadHeader(bytes memory serialized) internal pure returns (PayloadHeader memory header) {
        uint256 index = 0;

        // parse the header

        header.payloadID = serialized.toUint8(index);
        index += 1;
        header.sender = serialized.toAddress(index);
    }

    function extractSerializedFromTransferWithPayload(bytes memory encodedVM) internal pure returns (bytes memory serialized) {
        uint256 index = 0;
        uint256 end = encodedVM.length;

        // pass through TransferWithPayload metadata to arbitrary serialized bytes
        index += 1 + 32 + 32 + 2 + 32 + 2 + 32;

        return encodedVM.slice(index, end-index);
    }

    function decodeDepositPayload(bytes memory serialized) internal pure returns (DepositPayload memory params) {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(serialized.slice(index, 21));
        require(params.header.payloadID == 1, "invalid deposit message");
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

    function decodeWithdrawPayload(bytes memory serialized) internal pure returns (WithdrawPayload memory params) {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(serialized.slice(index, 21));
        require(params.header.payloadID == 2, "invalid withdraw message");
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

    function decodeBorrowPayload(bytes memory serialized) internal pure returns (BorrowPayload memory params) {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(serialized.slice(index, 21));
        require(params.header.payloadID == 3, "invalid borrow message");
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

    function decodeRepayPayload(bytes memory serialized) internal pure returns (RepayPayload memory params) {
        uint256 index = 0;

        // parse the payload header
        params.header = decodePayloadHeader(serialized.slice(index, 21));
        require(params.header.payloadID == 4, "invalid repay message");
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
    
    function decodeRegisterAssetPayload(bytes memory serialized)
        internal
        pure
        returns (RegisterAssetPayload memory params)
    {
        uint256 index = 0;

        // parse the message header
        params.header = decodePayloadHeader(serialized.slice(index, 21));
        require(params.header.payloadID == 5, "invalid register asset message");
        index += 21;

        // parse the asset address
        address assetAddress = serialized.toAddress(index);
        index += 20;

        params.assetAddress = assetAddress;

        // parse the collateralization ratio (deposit)
        uint256 collateralizationRatioDeposit = serialized.toUint256(index);
        index += 32;

        params.collateralizationRatioDeposit = collateralizationRatioDeposit;

        // parse the collateralization ratio (borrow)
        uint256 collateralizationRatioBorrow = serialized.toUint256(index);
        index += 32;

        params.collateralizationRatioBorrow = collateralizationRatioBorrow;

        // parse the Pyth Id
        // TODO: is this valid?? better way to do the conversion from bytes to bytes32
        bytes32 pythId = bytes32(serialized.toUint256(index)); //serialized[index:index+4];
        index += 4;

        params.pythId = pythId;

        // parse the rate precision
        uint64 ratePrecision = serialized.toUint64(index);
        index += 8;

        params.ratePrecision = ratePrecision;

        // parse the rate intercept
        uint64 rateIntercept = serialized.toUint64(index);
        index += 8;

        params.rateIntercept = rateIntercept;

        // parse the rate coefficient A
        uint64 rateCoefficientA = serialized.toUint64(index);
        index += 8;

        params.rateCoefficientA = rateCoefficientA;

        // parse the reserve factor
        uint256 reserveFactor = serialized.toUint256(index);
        index += 32;

        params.reserveFactor = reserveFactor;

        // parse the reserve precision
        uint256 reservePrecision = serialized.toUint256(index);
        index += 32;

        params.reservePrecision = reservePrecision;

        // parse the decimals
        uint8 decimals = serialized.toUint8(index);
        index += 1;

        params.decimals = decimals;
    }
}
