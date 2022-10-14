// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hub} from "../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../src/contracts/lendingHub/HubMessages.sol";
import {MyERC20} from "./helpers/MyERC20.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract HubTest is Test, HubStructs, HubMessages {
    MyERC20[] tokens;
    string[] tokenNames = ["BNB", "ETH", "USDC", "SOL", "AVAX"];
    Hub hub;

    function setUp() public {
        hub = new Hub(msg.sender, msg.sender, msg.sender, 1);

        for (uint8 i = 0; i < tokenNames.length; i++) {
            tokens.push(new MyERC20(tokenNames[i], tokenNames[i], 18));
        }
    }

    function testEncodeDepositPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 1,
            sender: address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = address(tokens[0]);
        uint256 assetAmount = 502;
        
        DepositPayload memory myPayload = DepositPayload({
            header: header,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });
        bytes memory serialized = encodeDepositPayload(myPayload);
        DepositPayload memory encodedAndDecodedMsg = decodeDepositPayload(
            serialized
        );

        require(
            myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID,
            "payload ids do not match"
        );
        require(
            myPayload.header.sender == encodedAndDecodedMsg.header.sender,
            "sender addresses do not match"
        );
        require(
            myPayload.assetAddress ==
                encodedAndDecodedMsg.assetAddress,
            "asset addresses do not match "
        );
        require(
            myPayload.assetAmount ==
                encodedAndDecodedMsg.assetAmount,
            "asset amounts do not match "
        );
    }

    function testEncodeWithdrawPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 2,
            sender: address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = address(tokens[0]);
        uint256 assetAmount = 2356;
        
        WithdrawPayload memory myPayload = WithdrawPayload({
            header: header,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });
        bytes memory serialized = encodeWithdrawPayload(myPayload);
        WithdrawPayload memory encodedAndDecodedMsg = decodeWithdrawPayload(
            serialized
        );

        require(
            myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID,
            "payload ids do not match"
        );
        require(
            myPayload.header.sender == encodedAndDecodedMsg.header.sender,
            "sender addresses do not match"
        );
        require(
            myPayload.assetAddress ==
                encodedAndDecodedMsg.assetAddress,
            "asset addresses do not match "
        );
        require(
            myPayload.assetAmount ==
                encodedAndDecodedMsg.assetAmount,
            "asset amounts do not match "
        );
    }


    function testEncodeBorrowPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 3,
            sender: address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = address(tokens[0]);
        uint256 assetAmount = 1242;
        
        BorrowPayload memory myPayload = BorrowPayload({
            header: header,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });
        bytes memory serialized = encodeBorrowPayload(myPayload);
        BorrowPayload memory encodedAndDecodedMsg = decodeBorrowPayload(
            serialized
        );

        require(
            myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID,
            "payload ids do not match"
        );
        require(
            myPayload.header.sender == encodedAndDecodedMsg.header.sender,
            "sender addresses do not match"
        );
        require(
            myPayload.assetAddress ==
                encodedAndDecodedMsg.assetAddress,
            "asset addresses do not match "
        );
        require(
            myPayload.assetAmount ==
                encodedAndDecodedMsg.assetAmount,
            "asset amounts do not match "
        );
    }

    function testEncodeRepayPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 4,
            sender: address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = address(tokens[0]);
        uint256 assetAmount = 4253;
        
        RepayPayload memory myPayload = RepayPayload({
            header: header,
            assetAddress: assetAddress,
            assetAmount: assetAmount
        });
        bytes memory serialized = encodeRepayPayload(myPayload);
        RepayPayload memory encodedAndDecodedMsg = decodeRepayPayload(
            serialized
        );

        require(
            myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID,
            "payload ids do not match"
        );
        require(
            myPayload.header.sender == encodedAndDecodedMsg.header.sender,
            "sender addresses do not match"
        );
        require(
            myPayload.assetAddress ==
                encodedAndDecodedMsg.assetAddress,
            "asset addresses do not match "
        );
        require(
            myPayload.assetAmount ==
                encodedAndDecodedMsg.assetAmount,
            "asset amounts do not match "
        );
    }

   
}
