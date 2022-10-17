// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./SpokeSetters.sol";
import "../lendingHub/HubStructs.sol";
import "../lendingHub/HubMessages.sol";
import "./SpokeGetters.sol";

contract Spoke is HubStructs, HubMessages, SpokeSetters, SpokeGetters {
    constructor(uint16 chainId_, address wormhole_, address tokenBridge_) {
        setOwner(_msgSender());
        setChainId(chainId_);
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
    }

    function completeRegisterAsset(bytes calldata encodedMessage) public {
        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);
        RegisterAssetPayload memory params = decodeRegisterAssetPayload(vmPayload);
        allowAsset(params.assetAddress);
        AssetInfo memory info = AssetInfo({
            collateralizationRatio: params.collateralizationRatio,
            reserveFactor: params.reserveFactor,
            pythId: params.pythId,
            decimals: params.decimals,
            exists: true
        });
        registerAssetInfo(params.assetAddress, info);        
    }

    function depositCollateral(address assetAddress, uint256 assetAmount) public returns (uint64) {
        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 1,
            sender: address(this)
        });

        DepositPayload memory depositPayload = DepositPayload({
            header: payloadHeader,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });

        // create WH message
        bytes memory serialized = encodeDepositPayload(depositPayload);

        // TODO: Send a token bridge message
    }

    function withdrawCollateral(address assetAddress, uint256 assetAmount) public returns (uint64 sequence) {
        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 2,
            sender: address(this)
        });

        WithdrawPayload memory withdrawPayload = WithdrawPayload({
            header: payloadHeader,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });

        // create WH message
        bytes memory serialized = encodeWithdrawPayload(withdrawPayload);

        sequence = sendWormholeMessage(serialized);
    }

    function borrow(address assetAddress, uint256 assetAmount) public returns (uint64 sequence) {
        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 3,
            sender: address(this)
        });

        BorrowPayload memory borrowPayload = BorrowPayload({
            header: payloadHeader,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });

        // create WH message
        bytes memory serialized = encodeBorrowPayload(borrowPayload);

        sequence = sendWormholeMessage(serialized);
    }

    function repay(address assetAddress, uint256 assetAmount) public returns (uint64) {
        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 4,
            sender: address(this)
        });

        RepayPayload memory repayPayload = RepayPayload({
            header: payloadHeader,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });

<<<<<<< HEAD
=======
        // create WH message
        bytes memory serialized = encodeRepayPayload(repayPayload);

        // TODO: Send a token bridge message
    }
>>>>>>> 4a50fa5 (Implementation of spoke methods without tokenbridge)

    function sendWormholeMessage(bytes memory payload)
        internal
        returns (uint64 sequence)
    {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }
}