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
    address wrappedGasTokenAddress;

    function setUp() public {
        
        testSetUp(vm);

        addAsset(AddAsset({
                assetAddress: 0x442F7f22b1EE2c842bEAFf52880d4573E9201158, // WBNB
                collateralizationRatioDeposit: 100 * 10 ** 16,
                collateralizationRatioBorrow: 110 * 10 ** 16,
                ratePrecision: 1 * 10**18,
                rateIntercept: 0,
                rateCoefficientA: 0,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_AVAX_bnb")  
        }));

        addAsset(AddAsset({assetAddress: 0x8b82A291F83ca07Af22120ABa21632088fC92931, // WETH
                collateralizationRatioDeposit: 100 * 10 ** 16,
                collateralizationRatioBorrow: 110 * 10 ** 16,
                ratePrecision: 1 * 10**18,
                rateIntercept: 0,
                rateCoefficientA: 0,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_AVAX_eth") 
    }));

        addAsset(AddAsset({assetAddress: address(getHubData().tokenBridgeContract.WETH()), // WAVAX
                collateralizationRatioDeposit: 100 * 10 ** 16,
                collateralizationRatioBorrow: 110 * 10 ** 16,
                ratePrecision: 1 * 10**18,
                rateIntercept: 0,
                rateCoefficientA: 0,
                reserveFactor: 0,
                 pythId: vm.envBytes32("PYTH_PRICE_FEED_AVAX_avax") 
        }));
        
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
        doRegisterAsset(getAsset(2));

    }


    function testRD() public {
        doRegisterSpoke(0);

        doDepositRevert(0, getAsset(0), 0, "Unregistered asset");

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
        setPrice(getAsset(1), 91);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);

        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Vault is undercollateralized if this borrow goes through");

        setPrice(getAsset(1), 90);

        doBorrow(0, getAsset(1), 5 * 10 ** 16);
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

        doWithdrawRevert(
            0, getAsset(0), 5 * 10 ** 14 + 1 * 10 ** 10, "Vault is undercollateralized if this withdraw goes through"
        );

        doWithdraw(0, getAsset(0), 5 * 10 ** 14);
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

        doRepay(0, getAsset(1), 5 * 10 ** 16 - 1 * 10 ** 10);

        doWithdrawRevert(0, getAsset(0), 5 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");

        doRepay(0, getAsset(1), 1 * 10 ** 10);

        doWithdraw(0, getAsset(0), 5 * 10 ** 16);
    }

    function testRDBL() public {
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
        assetRepayAmounts[0] = 250 * 10 ** 14;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "vault not underwater");

        // move the price up for borrowed asset
        setPrice(getAsset(1), 95);

        // liquidation attempted by address(this)
        assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = getAssetAddress(1);
        assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 250 * 10 ** 14;
        assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 240 * 10 ** 14;

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // try repayment of the borrow, should not execute the repayment because liquidation already occured
        doRepayRevertPayment(0, getAsset(1), 400 * 10 ** 14, address(0x1));
    }



    function testRDNative() public {

        doRegisterSpoke(0);

        doDepositNativeRevert(0, 5 * (10 ** 16), "Unregistered asset");

        doRegisterAsset(getAsset(2));

        vm.deal(address(this), 5 * 10 ** 16);

        doDepositNative(0, 5 * (10 ** 16));

    }

    function testRDNativeB() public {

        deal(getAssetAddress(0), address(0x1), 100 * 10 ** 16);

        vm.deal(address(this), 200 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 200 * 10 ** 16);

        doDeposit(0, getAsset(0), 100 * 10 ** 16, address(0x1));

        doBorrowRevert(0, getAsset(2), 81 * 10 ** 16, "Vault is undercollateralized if this borrow goes through", address(0x1));

        doBorrow(0, getAsset(2), 80 * 10 ** 16, address(0x1));

        doRepay(0, getAsset(2), 80 * 10 ** 16, address(0x1));

        setPrice(getAsset(0), 125);

        doBorrowRevert(0, getAsset(2), 127 * 10 ** 16, "Vault is undercollateralized if this borrow goes through", address(0x1));

        doBorrow(0, getAsset(2), 126 * 10 ** 16, address(0x1));
    }

    function testRDNativeBPW() public {
        address user = address(this);

        deal(getAssetAddress(0), user, 6 * 10 ** 16);
        uint256 userInitBalance = 105 * 10 ** 18;
        vm.deal(user, userInitBalance);
        vm.deal(address(0x1), userInitBalance);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 5 * 10 ** 16, address(0x1));

        doDeposit(0, getAsset(0), 6 * 10 ** 16);

        doBorrow(0, getAsset(2), 4 * 10 ** 16);

        doRepayNative(0, 2 * 10 ** 16);

        doWithdrawRevert(0, getAsset(0), 4 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");

        doRepayNative(0, 1 * 10 ** 16);

        doWithdraw(0, getAsset(0), 4 * 10 ** 16);
    }

    // test register SPOKE (make sure nothing is possible without doing this)


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
        uint16 reversionPaymentChainId = 2;

        RepayPayload memory myPayload =
            RepayPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount, reversionPaymentChainId: reversionPaymentChainId});
        bytes memory serialized = encodeRepayPayload(myPayload);
        RepayPayload memory encodedAndDecodedMsg = decodeRepayPayload(serialized);

        require(myPayload.header.payloadID == encodedAndDecodedMsg.header.payloadID, "payload ids do not match");
        require(myPayload.header.sender == encodedAndDecodedMsg.header.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
        require(myPayload.reversionPaymentChainId == encodedAndDecodedMsg.reversionPaymentChainId, "reversion payment chain ids do not match");
    }
}
