// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/libraries/external/BytesLib.sol";

import {Hub} from "../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../src/contracts/lendingHub/HubMessages.sol";
import {HubUtilities} from "../src/contracts/lendingHub/HubUtilities.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../src/interfaces/ITokenImplementation.sol";

import "../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./helpers/WormholeSimulator.sol";

import {TestHelpers} from "./helpers/TestHelpers.sol";
import {TestStructs} from "./helpers/TestStructs.sol";
import {TestState} from "./helpers/TestState.sol";
import {TestSetters} from "./helpers/TestSetters.sol";
import {TestGetters} from "./helpers/TestGetters.sol";

import {Spoke} from "../src/contracts/lendingSpoke/Spoke.sol";

import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract HubTest is Test, HubStructs, HubMessages, HubGetters, HubUtilities, TestStructs, TestState, TestGetters, TestSetters, TestHelpers {
    using BytesLib for bytes;


    // action codes
    // register: R
    // deposit: D
    // borrow: B
    // withdraw: W
    // repay: P
    // liquidation: L
    // fake spoke: FS

    function setUp() public {
        
        testSetUp(vm);

        addAsset(0x442F7f22b1EE2c842bEAFf52880d4573E9201158, // WBNB
                100 * 10 ** 16,
                110 * 10 ** 16,
                0,
                 vm.envBytes32("PYTH_PRICE_FEED_AVAX_bnb")  
        );

        addAsset(0x8b82A291F83ca07Af22120ABa21632088fC92931, // WETH
                100 * 10 ** 16,
                110 * 10 ** 16,
                0,
                vm.envBytes32("PYTH_PRICE_FEED_AVAX_eth") 
        );

        

        for (uint256 i = 0; i < 2; i++) {
            getHub().setMockPythFeed(
                getAsset(i).pythId, 0, 0, 0, 0, 0, 1
            );
        }

        addSpoke(
            uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")),
            vm.envAddress("TESTING_WORMHOLE_ADDRESS_AVAX"),
            vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")
        );
    }

    function testR() public {
        doRegisterSpoke(0);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));
    }

    function testD_Fail() public {
        doRegisterSpoke(0);

        doDepositRevert(0, getAsset(0), 0, "Unregistered asset");
    }

    function testRD() public {
        doRegisterSpoke(0);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        deal(getAssetAddress(1), address(this), 1 * 10 ** 17);
        deal(getAssetAddress(0), address(this), 5 * (10 ** 16));

        doDeposit(0, getAsset(1), 1 * 10 ** 17);
        doDeposit(0, getAsset(0), 5 * (10 ** 16));
    }

    function testRDB() public {
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);

        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);
    }

    function testRDB_Fail() public {
        // Should fail because the price of the borrow asset is a little too high

        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 91);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);

        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Vault is undercollateralized if this borrow goes through");
    }

    function testRDBW() public {
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);

        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doWithdraw(0, getAsset(0), 5 * 10 ** 14);
    }

    function testRDBW_Fail() public {
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);
        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doWithdrawRevert(
            0, getAsset(0), 5 * 10 ** 14 + 1 * 10 ** 10, "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBPW() public {
        deal(getAssetAddress(0), address(this), 5* 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 5* 10 ** 16);
        
        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doRepay(0, getAsset(1), 5 * 10 ** 16);

        doWithdraw(0, getAsset(0), 5 * 10 ** 16);
    }

    function testRDBPW_Fail() public {
        // Should fail because still some debt out so cannot withdraw all your deposited assets
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);
     
        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doRepay(0, getAsset(1), 5 * 10 ** 16 - 1 * 10 ** 10);

        doWithdrawRevert(0, getAsset(0), 5 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");
    }

    function testRDBL_Fail() public {
        // should fail because vault not underwater
        deal(getAssetAddress(0), address(this), 501 * 10 ** 14);
        deal(getAssetAddress(1), address(this), 1100 * 10 ** 14);
        deal(getAssetAddress(0), address(0x1), 500 * 10 ** 14);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 500 * 10 ** 14, address(0x1));

        doDeposit(0, getAsset(1), 600 * 10 ** 14);

        doBorrow(0, getAsset(1), 500 * 10 ** 14, address(0x1));

        // liquidation attempted by address(this)
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = getAssetAddress(1);
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 14;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;

        vm.expectRevert(bytes("vault not underwater"));
        getHub().liquidation(
            address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );
    }

    function testRDBL() public {
        address vault = address(this);
        address vaultOther = address(0x1);

        // prank mint with tokens
        deal(getAssetAddress(0), vault, 1000 * 10 ** 16);
        deal(getAssetAddress(1), vault, 2000 * 10 ** 16);
        deal(getAssetAddress(0), vaultOther, 3000 * 10 ** 16);
        deal(getAssetAddress(1), vaultOther, 4000 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 500 * 10 ** 14, vaultOther);
        doDeposit(0, getAsset(1), 600 * 10 ** 14);
        doBorrow(0, getAsset(1), 500 * 10 ** 14, vaultOther);

        // move the price up for borrowed asset
        setPrice(getAsset(1), 95);

        // liquidation attempted by address(this)
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = getAssetAddress(1);
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 14;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 490 * 10 ** 14;

        IERC20(getAssetAddress(1)).approve(address(getHub()), 500 * 10 ** 14);

        // get vault token balances pre liquidation
        uint256 balance_vault_0_pre = IERC20(getAssetAddress(0)).balanceOf(vault);
        uint256 balance_vault_1_pre = IERC20(getAssetAddress(1)).balanceOf(vault);
        // get hub contract token balances pre liquidation
        uint256 balance_hub_0_pre = IERC20(getAssetAddress(0)).balanceOf(address(getHub()));
        uint256 balance_hub_1_pre = IERC20(getAssetAddress(1)).balanceOf(address(getHub()));

        getHub().liquidation(vaultOther, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // get vault token balances post liquidation
        uint256 balance_vault_0_post = IERC20(getAssetAddress(0)).balanceOf(vault);
        uint256 balance_vault_1_post = IERC20(getAssetAddress(1)).balanceOf(vault);
        // get hub contract token balances post liquidation
        uint256 balance_hub_0_post = IERC20(getAssetAddress(0)).balanceOf(address(getHub()));
        uint256 balance_hub_1_post = IERC20(getAssetAddress(1)).balanceOf(address(getHub()));

        require(
            balance_vault_0_pre + balance_hub_0_pre == balance_vault_0_post + balance_hub_0_post,
            "Asset 0 total amounts should not change after liquidation"
        );
        require(
            balance_vault_1_pre + balance_hub_1_pre == balance_vault_1_post + balance_hub_1_post,
            "Asset 1 total amounts should not change after liquidation"
        );
    }


    /*
    *       TESTING ENCODING AND DECODING OF MESSAGES
    */

    function testEncodeDepositPayload() public view {
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = getAssetAddress(0);
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
        address assetAddress = getAssetAddress(0);
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
        address assetAddress = getAssetAddress(0);
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
        address assetAddress = getAssetAddress(0);
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
