// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/libraries/external/BytesLib.sol";

import {Hub} from "../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../src/contracts/lendingHub/HubMessages.sol";
import {HubUtilities} from "../src/contracts/lendingHub/HubUtilities.sol";
import {MyERC20} from "./helpers/MyERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../src/interfaces/ITokenImplementation.sol";

import "../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./helpers/WormholeSimulator.sol";

import {TestHelpers} from "./helpers/TestHelpers.sol";


contract HubTest is Test, HubStructs, HubMessages, HubGetters, HubUtilities, TestHelpers {
    using BytesLib for bytes;

    // TODO: Decide what data goes where.. what makes sense here?
    WormholeData wormholeData;
    WormholeSpokeData wormholeSpokeData;
    TestToken[] tokens;

    function setUp() public {
        (wormholeData, wormholeSpokeData) = testSetUp(vm, tokens);
    }


    // test register
    function testRegister() public {
        address assetAddress = tokens[0].tokenAddress;

        // register asset
        doRegister(assetAddress, tokens[0].collateralizationRatio, 0, bytes32(0), 18, wormholeData, wormholeSpokeData);

        AssetInfo memory info = wormholeData.hub.getAssetInfo(assetAddress);

        require(
            (info.collateralizationRatio == tokens[0].collateralizationRatio) && (info.decimals == 18) && (info.exists),
            "didn't register properly"
        );
    }

    // action codes
    // register: R
    // deposit: D
    // borrow: B
    // withdraw: W
    // repay: P
    // liquidation: L

    function testRD() public {
        address vault = msg.sender;
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 502;
        uint256 collateralizationRatio = tokens[0].collateralizationRatio;
        uint8 decimals = 18;
        uint256 reserveFactor = 0;
        bytes32 pythId = bytes32(0);

        // call register
        // TODO: make the syntax just doRegister(token)
        doRegister(assetAddress, collateralizationRatio, reserveFactor, pythId, decimals, wormholeData, wormholeSpokeData);

        AssetInfo memory info = wormholeData.hub.getAssetInfo(assetAddress);

        VaultAmount memory globalBefore = wormholeData.hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = wormholeData.hub.getVaultAmounts(vault, assetAddress);

        // call deposit
        doDeposit(vault, assetAddress, assetAmount, wormholeData, wormholeSpokeData);

        VaultAmount memory globalAfter = wormholeData.hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = wormholeData.hub.getVaultAmounts(vault, assetAddress);
        // TODO: why does specifying msg.sender fix all?? Seems it assumes incorrect msg.sender by default
        
        require(globalBefore.deposited == 0, "Deposited not initialized to 0");
        require(globalAfter.deposited == 502 * 10**decimals , "502 wasn't deposited (globally)");

        require(vaultBefore.deposited == 0, "Deposited not initialized to 0");
        require(vaultAfter.deposited == 502 * 10**decimals, "502 wasn't deposited (in the vault)");
    }

    function testD() public {
        // TODO: how to use expectRevert when error is triggered in other file
        // vm.expectRevert("Unregistered asset");

        address vault = msg.sender;
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 502;
        uint256 collateralizationRatio = tokens[0].collateralizationRatio;
        uint8 decimals = 18;
        uint256 reserveFactor = 0;
        bytes32 pythId = bytes32(0);

        doDeposit(vault, assetAddress, assetAmount, wormholeData, wormholeSpokeData);
    }

    function testRDB() public {
        // TODO: work out how to set Pyth price
        address vault = msg.sender;
        address assetAddress0 = tokens[0].tokenAddress;
        uint256 assetAmount0 = 502;
        uint256 collateralizationRatio0 = tokens[0].collateralizationRatio;
        uint8 decimals0 = 18;
        uint256 reserveFactor0 = 0;
        bytes32 pythId0 = bytes32("BNB");

        address assetAddress1 = tokens[1].tokenAddress;
        uint256 assetAmount1 = 500;
        uint256 collateralizationRatio1 = tokens[1].collateralizationRatio;
        uint8 decimals1 = 18;
        uint256 reserveFactor1 = 0;
        bytes32 pythId1 = bytes32("SOL");

        // call register
        doRegister(assetAddress0, collateralizationRatio0, reserveFactor0, pythId0, decimals0, wormholeData, wormholeSpokeData);
        doRegister(assetAddress1, collateralizationRatio1, reserveFactor1, pythId1, decimals1, wormholeData, wormholeSpokeData);

        AssetInfo memory info0 = wormholeData.hub.getAssetInfo(assetAddress0);
        AssetInfo memory info1 = wormholeData.hub.getAssetInfo(assetAddress1);

        // call deposit
        doDeposit(vault, assetAddress0, assetAmount0, wormholeData, wormholeSpokeData);

        // set Oracle price for asset deposited
        int64 price0 = 100;
        uint64 conf0 = 10;
        int32 expo0 = 0;
        uint publishTime0 = 1;
        Price memory oraclePrice0 = Price({
            price: price0,
            conf: conf0,
            expo: expo0,
            publishTime: publishTime0
        });
        wormholeData.hub.setOraclePrice(info0.pythId, oraclePrice0);

        // set Oracle price for asset intended to be borrowed
        int64 price1 = 50;
        uint64 conf1 = 5;
        int32 expo1 = 0;
        uint publishTime1 = 1;
        Price memory oraclePrice1 = Price({
            price: price1,
            conf: conf1,
            expo: expo1,
            publishTime: publishTime1
        });
        wormholeData.hub.setOraclePrice(info1.pythId, oraclePrice1);

        // call borrow
        doBorrow(vault, assetAddress1, assetAmount1, wormholeData, wormholeSpokeData);
    }
    
    /*
    *       TESTING ENCODING AND DECODING OF MESSAGES
    */

        function testEncodeDepositPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 502;

        DepositPayload memory myPayload =
            DepositPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeDepositPayload(myPayload);

        DepositPayload memory encodedAndDecodedMsg = decodeDepositPayload(serialized);

        require(myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID, "payload ids do not match");
        require(myPayload.header.sender == encodedAndDecodedMsg.header.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeWithdrawPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 2,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 2356;

        WithdrawPayload memory myPayload =
            WithdrawPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeWithdrawPayload(myPayload);
        WithdrawPayload memory encodedAndDecodedMsg = decodeWithdrawPayload(serialized);

        require(myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID, "payload ids do not match");
        require(myPayload.header.sender == encodedAndDecodedMsg.header.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeBorrowPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 3,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 1242;

        BorrowPayload memory myPayload =
            BorrowPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeBorrowPayload(myPayload);
        BorrowPayload memory encodedAndDecodedMsg = decodeBorrowPayload(serialized);

        require(myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID, "payload ids do not match");
        require(myPayload.header.sender == encodedAndDecodedMsg.header.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeRepayPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 4,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = tokens[0].tokenAddress;
        uint256 assetAmount = 4253;

        RepayPayload memory myPayload =
            RepayPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeRepayPayload(myPayload);
        RepayPayload memory encodedAndDecodedMsg = decodeRepayPayload(serialized);

        require(myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID, "payload ids do not match");
        require(myPayload.header.sender == encodedAndDecodedMsg.header.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }
}
