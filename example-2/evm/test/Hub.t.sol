// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/libraries/external/BytesLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HubSpokeStructs} from "../src/contracts/HubSpokeStructs.sol";
import {HubSpokeMessages} from "../src/contracts/HubSpokeMessages.sol";
import {TestHelpers} from "./helpers/TestHelpers.sol";
import {TestStructs} from "./helpers/TestStructs.sol";
import {TestState} from "./helpers/TestState.sol";
import {TestSetters} from "./helpers/TestSetters.sol";
import {TestGetters} from "./helpers/TestGetters.sol";

contract HubTest is Test, HubSpokeStructs, HubSpokeMessages, TestStructs, TestState, TestGetters, TestSetters, TestHelpers {
    using BytesLib for bytes;

    /* action codes
       register: R
       deposit: D
       borrow: B
       withdraw: W
       repay: P
       liquidation: L */

    function setUp() public {
        
        testSetUp(vm);

        uint256[] memory kinks0 = new uint256[](2);
        kinks0[0] = 0;
        kinks0[1] = 1 * 10**6;
        uint256[] memory rates0 = new uint256[](2);
        rates0[0] = 0;
        rates0[1] = 0;

        addAsset(AddAsset({
                assetAddress: 0xF8542587BCaFCA72D78f29734cE8Ccf08fCd5E5D, // WBNB
                collateralizationRatioDeposit: 100 * 10 ** 4,
                collateralizationRatioBorrow: 110 * 10 ** 4,
                ratePrecision: 1 * 10**6,
                kinks: kinks0,
                rates: rates0,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_bnb")  
        }));

        uint256[] memory kinks1 = new uint256[](2);
        kinks1[0] = 0;
        kinks1[1] = 1 * 10**6;
        uint256[] memory rates1 = new uint256[](2);
        rates1[0] = 0;
        rates1[1] = 0;

        addAsset(AddAsset({assetAddress: 0xc6735cc74553Cc2caeB9F5e1Ea0A4dAe12ef4632, // WETH
                collateralizationRatioDeposit: 100 * 10 ** 4,
                collateralizationRatioBorrow: 110 * 10 ** 4,
                ratePrecision: 1 * 10**6,
                kinks: kinks1,
                rates: rates1,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_eth") 
        }));

        uint256[] memory kinks2 = new uint256[](2);
        kinks2[0] = 0;
        kinks2[1] = 1 * 10**6;
        uint256[] memory rates2 = new uint256[](2);
        rates2[0] = 0;
        rates2[1] = 0;

        addAsset(AddAsset({assetAddress: address(getHubData().tokenBridgeContract.WETH()), 
                collateralizationRatioDeposit: 100 * 10 ** 4,
                collateralizationRatioBorrow: 110 * 10 ** 4,
                ratePrecision: 1 * 10**6,
                kinks: kinks2,
                rates: rates2,
                reserveFactor: 0,
                 pythId: vm.envBytes32("PYTH_PRICE_FEED_matic") 
        }));

        uint256[] memory kinks3 = new uint256[](2);
        kinks3[0] = 0;
        kinks3[1] = 1 * 10**6;
        uint256[] memory rates3 = new uint256[](2);
        rates3[0] = 1 * 10**4;
        rates3[1] = 1 * 10**4;

        addAsset(AddAsset({assetAddress: 0xF8542587BCaFCA72D78f29734cE8Ccf08fCd5E5D, 
                collateralizationRatioDeposit: 100 * 10 ** 4,
                collateralizationRatioBorrow: 100 * 10 ** 4,
                ratePrecision: 1 * 10**6,
                kinks: kinks3,
                rates: rates3,
                reserveFactor: 0,
                 pythId: vm.envBytes32("PYTH_PRICE_FEED_bnb") 
        }));
        
        addSpoke(
            uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_MUMBAI")),
            vm.envAddress("TESTING_WORMHOLE_ADDRESS_MUMBAI"),
            vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_MUMBAI")
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

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Global supply does not have required assets");

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

        doWithdrawRevert(
            0, getAsset(1), 6 * 10 ** 16 + 1 * 10 ** 10, address(0x1), "Vault does not have required assets"
        );

        doWithdrawRevert(
            0, getAsset(1), 6 * 10 ** 16, address(0x1), "Global supply does not have required assets"
        );
    }


    function testRDBPW() public {
        deal(getAssetAddress(0), address(this), 5* 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);
        deal(getAssetAddress(1), address(this), 1 * 10 ** 10);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke(0);

        doDeposit(0, getAsset(0), 5* 10 ** 16);
        
        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doRepayRevertPayment(0, getAsset(1), 5 * 10 ** 16 + 1 * 10 ** 10);

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
      
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);

        assetRepayAmounts[0] = 1 * 10 ** 14;
        assetReceiptAmounts[0] = 1 * 10 ** 14;
        
        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "vault not underwater");

        // move the price up for borrowed asset
        setPrice(getAsset(1), 91);

        assetRepayAmounts[0] = 501 * 10 ** 14;
        assetReceiptAmounts[0] = 501 * 10 ** 14;

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "cannot repay more than has been borrowed");

        assetRepayAmounts[0] = 1 * 10 ** 14;
        assetReceiptAmounts[0] = 90 * 10 ** 12; 

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "Liquidator receipt less than amount they repaid");

        assetRepayAmounts[0] = 251 * 10 ** 14;
        assetReceiptAmounts[0] = 251 * 10 ** 14; 

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "Liquidator cannot claim more than maxLiquidationPortion of the total debt of the vault");

        assetRepayAmounts[0] = 250 * 10 ** 14;
        assetReceiptAmounts[0] = 250 * 10 ** 10 * 91 * 126; 

        doLiquidate(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts, "Liquidator receiving too much value");

        assetRepayAmounts[0] = 250 * 10 ** 14;
        assetReceiptAmounts[0] = 250 * 10 ** 10 * 91 * 125; 

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

        deal(getAssetAddress(0), address(this), 6 * 10 ** 16);

        vm.deal(address(this), 105 * 10 ** 18);
        vm.deal(address(0x1), 105 * 10 ** 18);

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

    function testDontRegisterSpoke() public {

        deal(getAssetAddress(0), address(this), 105 * 10 ** 18);
        deal(getAssetAddress(2), address(this), 105 * 10 ** 18);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(2));

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositRevert(0, getAsset(0), 6 * 10 ** 16, "Invalid spoke");

        doBorrowRevert(0, getAsset(2), 4 * 10 ** 16, "Invalid spoke");

        doWithdrawRevert(0, getAsset(0), 4 * 10 ** 16, "Invalid spoke");

        doRepayRevert(0, getAsset(2), 4 * 10 ** 16, "Invalid spoke");
    }

    function testConstantInterestRate() public {

        setDebug(true);

        deal(getAssetAddress(3), address(this), 100 * 10 ** 18);
        deal(getAssetAddress(3), address(0x1), 100 * 10 ** 18);
        deal(getAssetAddress(2), address(this), 100 * 10 ** 18);

        doRegisterAsset(getAsset(3));
        doRegisterAsset(getAsset(2));

        setPrice(getAsset(2), 100);
        setPrice(getAsset(3), 100);

        doRegisterSpoke(0);
        
        doDeposit(0, getAsset(2), 1 * 10 ** 20);
        doDeposit(0, getAsset(3), 1 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(3), 1 * 10 ** 16);

        skip(365 days);

        doRepayRevertPayment(0, getAsset(3), 1 * 10 ** 16 + 1 * 10 ** 14 + 1 * 10 ** 10);

        doRepay(0, getAsset(3), 1 * 10 ** 16 + 1 * 10 ** 14);

        doWithdrawRevert(0, getAsset(3), 1 * 10 ** 16 + 1 * 10 ** 14 + 1 * 10 ** 10, address(0x1), "Vault does not have required assets");


        doWithdraw(0, getAsset(3), 1 * 10 ** 16 + 1 * 10 ** 14, address(0x1));


        doDeposit(0, getAsset(3), 2345675423 * 10 ** 10, address(0x1));

        doBorrow(0, getAsset(3), 2345675422 * 10 ** 10);

        skip(365 days / 2);

        doRepayRevertPayment(0, getAsset(3), 2357287678 * 10 ** 10);
        doRepay(0, getAsset(3), 2357287677 * 10 ** 10);
        doWithdrawRevert(0, getAsset(3), 2357285356 * 10 ** 10, address(0x1), "Vault does not have required assets");
        
        doWithdraw(0, getAsset(3), 2357285355 * 10 ** 10, address(0x1));

    }

    function testPriceStandardDev() public {
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(getAsset(0));
        doRegisterAsset(getAsset(1));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 1000000);
        setPrice(getAsset(1), 867600, 10000, 0, 100, 100);

        doDeposit(0, getAsset(0), 5 * 10 ** 16);

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Global supply does not have required assets");

        doDeposit(0, getAsset(1), 6 * 10 ** 16, address(0x1));

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Vault is undercollateralized if this borrow goes through");

        setPrice(getAsset(1), 857600, 10000, 0, 100, 100); 

        doBorrow(0, getAsset(1), 5 * 10 ** 16);

        doRepay(0, getAsset(1), 5 * 10 ** 16);

        setPrice(getAsset(0), 1032399, 10000, 0, 100, 100);

        doBorrowRevert(0, getAsset(1), 5 * 10 ** 16, "Vault is undercollateralized if this borrow goes through");

        setPrice(getAsset(0), 1032400, 10000, 0, 100, 100);
        
        doBorrow(0, getAsset(1), 5 * 10 ** 16);
    }




    /*
    *       TESTING ENCODING AND DECODING OF MESSAGES
    */

    function testEncodeDepositPayload() public view {
        address sender = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        address assetAddress = getAssetAddress(0);
        uint256 assetAmount = 502;

        ActionPayload memory myPayload =
            ActionPayload({action: Action.Deposit, sender: sender, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeActionPayload(myPayload);

        ActionPayload memory encodedAndDecodedMsg = decodeActionPayload(serialized);

        require(myPayload.action == encodedAndDecodedMsg.action, "actions do not match");
        require(myPayload.sender == encodedAndDecodedMsg.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeWithdrawPayload() public view {
        address sender = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        address assetAddress = getAssetAddress(0);
        uint256 assetAmount = 2356;

        ActionPayload memory myPayload =
            ActionPayload({action: Action.Withdraw, sender: sender, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeActionPayload(myPayload);

        ActionPayload memory encodedAndDecodedMsg = decodeActionPayload(serialized);

        require(myPayload.action == encodedAndDecodedMsg.action, "actions do not match");
        require(myPayload.sender == encodedAndDecodedMsg.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeBorrowPayload() public view {
        address sender = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        address assetAddress = getAssetAddress(0);
        uint256 assetAmount = 1242;

        ActionPayload memory myPayload =
            ActionPayload({action: Action.Borrow, sender: sender, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeActionPayload(myPayload);

        ActionPayload memory encodedAndDecodedMsg = decodeActionPayload(serialized);

        require(myPayload.action == encodedAndDecodedMsg.action, "actions do not match");
        require(myPayload.sender == encodedAndDecodedMsg.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }

    function testEncodeRepayPayload() public view {
        address sender = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        address assetAddress = getAssetAddress(0);
        uint256 assetAmount = 4253;

        ActionPayload memory myPayload =
            ActionPayload({action: Action.Repay, sender: sender, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeActionPayload(myPayload);

        ActionPayload memory encodedAndDecodedMsg = decodeActionPayload(serialized);

        require(myPayload.action == encodedAndDecodedMsg.action, "actions do not match");
        require(myPayload.sender == encodedAndDecodedMsg.sender, "sender addresses do not match");
        require(myPayload.assetAddress == encodedAndDecodedMsg.assetAddress, "asset addresses do not match ");
        require(myPayload.assetAmount == encodedAndDecodedMsg.assetAmount, "asset amounts do not match ");
    }
}
