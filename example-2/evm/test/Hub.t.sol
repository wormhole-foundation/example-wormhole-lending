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
    TestAsset[] assets;

    function setUp() public {
        (wormholeData, wormholeSpokeData) = testSetUp(vm, assets);
    }

    // test register SPOKE (make sure nothing is possible without doing this)

    // test register asset
    function testRegisterAsset() public {

        // register asset
        doRegister(assets[0], wormholeData, wormholeSpokeData);

        AssetInfo memory info = wormholeData.hub.getAssetInfo(assets[0].assetAddress);

        require(
            (info.collateralizationRatio == assets[0].collateralizationRatio) && (info.decimals == assets[0].decimals) && (info.pythId == assets[0].pythId) && (info.exists),
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
        address assetAddress = assets[0].assetAddress;
        // call register
        doRegister(assets[0], wormholeData, wormholeSpokeData);

        VaultAmount memory globalBefore = wormholeData.hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = wormholeData.hub.getVaultAmounts(vault, assetAddress);

        // call deposit
        doDeposit(vault, assetAddress, 502, wormholeData, wormholeSpokeData);

        VaultAmount memory globalAfter = wormholeData.hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = wormholeData.hub.getVaultAmounts(vault, assetAddress);
        // TODO: why does specifying msg.sender fix all?? Seems it assumes incorrect msg.sender by default
        
        require(globalBefore.deposited == 0, "Deposited not initialized to 0");
        require(globalAfter.deposited == 502 , "502 wasn't deposited (globally)");

        require(vaultBefore.deposited == 0, "Deposited not initialized to 0");
        require(vaultAfter.deposited == 502, "502 wasn't deposited (in the vault)");
    }

    function testFailD() public {
        // Should fail because there is no registered asset

        address vault = msg.sender;
        doDeposit(vault, assets[0].assetAddress, 502, wormholeData, wormholeSpokeData);
    }

    function testRDB() public {
        address vault = msg.sender;

        // call register
        doRegister(assets[0], wormholeData, wormholeSpokeData);
        doRegister(assets[1], wormholeData, wormholeSpokeData);

        // register spoke
        doRegisterSpoke(wormholeData, wormholeSpokeData);

        // call deposit
        doDeposit(vault, assets[0].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

        doDeposit(address(0), assets[1].assetAddress, 600 * 10 ** 18, wormholeData, wormholeSpokeData);

        // set Oracle price for asset deposited
        wormholeData.hub.setOraclePrice(assets[0].pythId, Price({
            price: 100,
            conf: 10, 
            expo: 1,
            publishTime: 1
        }));

        // set Oracle price for asset intended to be borrowed
        wormholeData.hub.setOraclePrice(assets[1].pythId, Price({
            price: 90,
            conf: 5,
            expo: 0,
            publishTime: 1
        }));

        // call borrow
        doBorrow(vault, assets[1].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

    }

    function testFailRDB() public {
        // Should fail because the price of the borrow asset is a little too high

        address vault = msg.sender;

        // call register
        doRegister(assets[0], wormholeData, wormholeSpokeData);
        doRegister(assets[1], wormholeData, wormholeSpokeData);

        // register spoke
        doRegisterSpoke(wormholeData, wormholeSpokeData);

        // call deposit
        doDeposit(vault, assets[0].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

        doDeposit(address(0), assets[1].assetAddress, 600 * 10 ** 18, wormholeData, wormholeSpokeData);

        // set Oracle price for asset deposited
        wormholeData.hub.setOraclePrice(assets[0].pythId, Price({
            price: 100,
            conf: 10, 
            expo: 1,
            publishTime: 1
        }));

        // set Oracle price for asset intended to be borrowed
        wormholeData.hub.setOraclePrice(assets[1].pythId, Price({
            price: 91,
            conf: 5,
            expo: 0,
            publishTime: 1
        }));

        // call borrow
        doBorrow(vault, assets[1].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

    }

    function testRDBW() public {
        address vault = msg.sender;

        // call register
        doRegister(assets[0], wormholeData, wormholeSpokeData);
        doRegister(assets[1], wormholeData, wormholeSpokeData);

        // register spoke
        doRegisterSpoke(wormholeData, wormholeSpokeData);

        // call deposit
        doDeposit(vault, assets[0].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

        doDeposit(address(0), assets[1].assetAddress, 600 * 10 ** 18, wormholeData, wormholeSpokeData);

        // set Oracle price for asset deposited
        wormholeData.hub.setOraclePrice(assets[0].pythId, Price({
            price: 100,
            conf: 10, 
            expo: 1,
            publishTime: 1
        }));

        // set Oracle price for asset intended to be borrowed
        wormholeData.hub.setOraclePrice(assets[1].pythId, Price({
            price: 90,
            conf: 5,
            expo: 0,
            publishTime: 1
        }));

        // call borrow
        doBorrow(vault, assets[1].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);
    
        doWithdraw(vault, assets[0].assetAddress, 500 * 10 ** 16, wormholeData, wormholeSpokeData);
    }

    function testFailRDBW() public {
        address vault = msg.sender;

        // call register
        doRegister(assets[0], wormholeData, wormholeSpokeData);
        doRegister(assets[1], wormholeData, wormholeSpokeData);

        // register spoke
        doRegisterSpoke(wormholeData, wormholeSpokeData);

        // call deposit
        doDeposit(vault, assets[0].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);

        doDeposit(address(0), assets[1].assetAddress, 600 * 10 ** 18, wormholeData, wormholeSpokeData);

        // set Oracle price for asset deposited
        wormholeData.hub.setOraclePrice(assets[0].pythId, Price({
            price: 100,
            conf: 10, 
            expo: 1,
            publishTime: 1
        }));

        // set Oracle price for asset intended to be borrowed
        wormholeData.hub.setOraclePrice(assets[1].pythId, Price({
            price: 90,
            conf: 5,
            expo: 0,
            publishTime: 1
        }));

        // call borrow
        doBorrow(vault, assets[1].assetAddress, 500 * 10 ** 18, wormholeData, wormholeSpokeData);
    
        doWithdraw(vault, assets[0].assetAddress, 500 * 10 ** 16 + 1, wormholeData, wormholeSpokeData);
    }
    
    /*
    *       TESTING ENCODING AND DECODING OF MESSAGES
    */

    function testEncodeDepositPayload() public view {
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = assets[0].assetAddress;
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

    function testEncodeWithdrawPayload() public view {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 2,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = assets[0].assetAddress;
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

    function testEncodeBorrowPayload() public view {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 3,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = assets[0].assetAddress;
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

    function testEncodeRepayPayload() public view {
        PayloadHeader memory header = PayloadHeader({
            payloadID: 4,
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = assets[0].assetAddress;
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
