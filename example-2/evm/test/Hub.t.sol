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
    
      TestAsset[] assets;
      Hub hub;

    function setUp() public {
        hub = testSetUp(vm);
        assets.push(
            TestAsset({
                assetAddress: 0x442F7f22b1EE2c842bEAFf52880d4573E9201158, // WBNB
                asset: IERC20(0x442F7f22b1EE2c842bEAFf52880d4573E9201158),
                collateralizationRatio: 110 * 10 ** 16,
                decimals: 18,
                reserveFactor: 0,
                pythId: bytes32("BNB")
            })
        );

        assets.push(
            TestAsset({
                assetAddress: 0xFE6B19286885a4F7F55AdAD09C3Cd1f906D2478F, // WSOL
                asset: IERC20(0xFE6B19286885a4F7F55AdAD09C3Cd1f906D2478F),
                collateralizationRatio: 110 * 10 ** 16,
                decimals: 18,
                reserveFactor: 0,
                pythId: bytes32("SOL")
            })
        );
    }

    // test register SPOKE (make sure nothing is possible without doing this)

    // test register asset
    function testRegisterAsset() public {

        // register asset
        doRegister(assets[0]);

        AssetInfo memory info = hub.getAssetInfo(assets[0].assetAddress);

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
        doRegister(assets[0]);

        VaultAmount memory globalBefore = hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = hub.getVaultAmounts(vault, assetAddress);

        // call deposit
        doDeposit(vault, assets[0], 502);

        VaultAmount memory globalAfter = hub.getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = hub.getVaultAmounts(vault, assetAddress);
        // TODO: why does specifying msg.sender fix all?? Seems it assumes incorrect msg.sender by default
        
        require(globalBefore.deposited == 0, "Deposited not initialized to 0");
        require(globalAfter.deposited == 502 , "502 wasn't deposited (globally)");

        require(vaultBefore.deposited == 0, "Deposited not initialized to 0");
        require(vaultAfter.deposited == 502, "502 wasn't deposited (in the vault)");
    }

    function testFailD() public {
        // Should fail because there is no registered asset
        address vault = msg.sender;
        doDeposit(vault, assets[0], 502);
    }

    function testRDB() public {
        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        doRegisterSpoke();

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);

    }

    function testFailRDB() public {
        // Should fail because the price of the borrow asset is a little too high

        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 91);

        doRegisterSpoke();

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);

    }

    function testRDBW() public {
        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke();

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);
    
        doWithdraw(vault, assets[0], 500 * 10 ** 16);
    }

    function testFailRDBW() public {
        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke();

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);
    
        doWithdraw(vault, assets[0], 500 * 10 ** 16 + 1);
    }

    function testRDBPW() public {
        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke();

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);

        doRepay(vault, assets[1], 500 * 10 ** 18);
    
        doWithdraw(vault, assets[0], 500 * 10 ** 18);
    }

    function testFailRDBPW() public {
        address vault = msg.sender;

        doRegister(assets[0]);
        doRegister(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke();

        doDeposit(vault, assets[0], 500 * 10 ** 18);
        doDeposit(address(0), assets[1], 600 * 10 ** 18);

        doBorrow(vault, assets[1], 500 * 10 ** 18);

        doRepay(vault, assets[1], 500 * 10 ** 18 - 1);
    
        doWithdraw(vault, assets[0], 500 * 10 ** 18);
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
