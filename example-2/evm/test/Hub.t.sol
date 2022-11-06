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

        addAsset(0x442F7f22b1EE2c842bEAFf52880d4573E9201158, // WBNB
                100 * 10 ** 16,
                110 * 10 ** 16,
                1 * 10**18,
                0,
                0,
                0,
                 vm.envBytes32("PYTH_PRICE_FEED_AVAX_bnb")  
        );

        addAsset(0x8b82A291F83ca07Af22120ABa21632088fC92931, // WETH
                100 * 10 ** 16,
                110 * 10 ** 16,
                1 * 10**18,
                0,
                0,
                0,
                vm.envBytes32("PYTH_PRICE_FEED_AVAX_eth") 
        );

        wrappedGasTokenAddress = address(getHubData().tokenBridgeContract.WETH());

        addAsset(wrappedGasTokenAddress, // WAVAX
                100 * 10 ** 16,
                110 * 10 ** 16,
                1 * 10**18,
                0,
                0,
                0,
                vm.envBytes32("PYTH_PRICE_FEED_AVAX_avax") 
        );
        

        for (uint256 i = 0; i < 3; i++) {
            int64 startPrice = 0;
            uint64 startConf = 0;
            int32 startExpo = 0;
            int64 startEmaPrice = 0;
            uint64 startEmaConf = 0;
            uint64 startPublishTime = 1;

            getHub().setMockPythFeed(
                getAsset(i).pythId, startPrice, startConf, startExpo, startEmaPrice, startEmaConf, startPublishTime
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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));
        doRegisterAsset(0, getAsset(2));
    }

    function testD_Fail() public {
        doRegisterSpoke(0);

        doDepositRevert(0, getAsset(0), 0, "Unregistered asset");
    }

    function testRD() public {
        doRegisterSpoke(0);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

        deal(getAssetAddress(1), address(this), 1 * 10 ** 17);
        deal(getAssetAddress(0), address(this), 5 * (10 ** 16));

        doDeposit(0, getAsset(1), 1 * 10 ** 17);
        doDeposit(0, getAsset(0), 5 * (10 ** 16));
    }

    function testRDB() public {
        deal(getAssetAddress(0), address(this), 5 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 16);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(1));

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
        // uint256 allowanceAmount = IERC20(getAssetAddress(1)).allowance(vault, address(getHub()));

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

        //console.log("balance of vault for token 0 went from ", balance_vault_0_pre, " to ", balance_vault_0_post);
        //console.log("balance of vault for token 1 went from ", balance_vault_1_pre, " to ", balance_vault_1_post);
        //console.log("balance of hub for token 0 went from ", balance_hub_0_pre, " to ", balance_hub_0_post);
        //console.log("balance of hub for token 1 went from ", balance_hub_1_pre, " to ", balance_hub_1_post);

        require(
            balance_vault_0_pre + balance_hub_0_pre == balance_vault_0_post + balance_hub_0_post,
            "Asset 0 total amounts should not change after liquidation"
        );
        require(
            balance_vault_1_pre + balance_hub_1_pre == balance_vault_1_post + balance_hub_1_post,
            "Asset 1 total amounts should not change after liquidation"
        );
    }

    function testRDNative() public {
        uint256 msgFee = getHubData().wormholeContract.messageFee();
        Hub hub = getHub();

        doRegisterAsset(0, getAsset(2));

        doRegisterSpoke(0);

        address user = address(this);

        uint256 userInitBalance = 105 * 10 ** 18;

        vm.deal(user, userInitBalance);
   
        VaultAmount memory globalBefore = hub.getGlobalAmounts(wrappedGasTokenAddress);
        VaultAmount memory vaultBefore = hub.getVaultAmounts(user, wrappedGasTokenAddress);

        uint256 balance_user_native_pre = address(user).balance;
        uint256 balance_hub_native_pre = IERC20(wrappedGasTokenAddress).balanceOf(address(hub));

        doDepositNative(0, 5 * (10 ** 16));

        uint256 balance_user_native_post = address(user).balance;

        uint256 balance_hub_native_post = IERC20(wrappedGasTokenAddress).balanceOf(address(hub));

        VaultAmount memory globalAfter = hub.getGlobalAmounts(wrappedGasTokenAddress);
        VaultAmount memory vaultAfter = hub.getVaultAmounts(user, wrappedGasTokenAddress);

        require(globalBefore.deposited == 0, "Deposited not initialized to 0");
        require(globalAfter.deposited == 5 * 10 ** 16 , "5 * 10 ** 16 wasn't deposited (globally)");

        require(vaultBefore.deposited == 0, "Deposited not initialized to 0");
        require(vaultAfter.deposited == 5 * 10 ** 16 - msgFee, "Amount minus WH msg fee wasn't deposited (in the vault)");

        require(balance_user_native_pre == userInitBalance , "User gas token balance not correct initially");

        require(balance_hub_native_pre == 0, "Hub gas token balance not 0 initially");

        require(balance_user_native_post == userInitBalance - 5 * (10 ** 16), "User gas token balance not correct after");

        require(balance_hub_native_post == 5 * (10 ** 16) - msgFee, "Hub gas token balance not correctly amount transferred minus WH msg fee after");
    }

    function testDNative_Fail() public {
        doRegisterSpoke(0);

        address user = address(this);

        uint256 userInitBalance = 105 * 10 ** 18;

        vm.deal(user, userInitBalance);

        doDepositNativeRevert(0, 5 * (10 ** 16), "Unregistered asset");
    }

    function testRDNativeB() public {
        address user = address(this);

        deal(getAssetAddress(0), address(0x1), 6 * 10 ** 16);
        uint256 userInitBalance = 105 * 10 ** 18;
        vm.deal(user, userInitBalance);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 5 * 10 ** 16);

        doDeposit(0, getAsset(0), 6 * 10 ** 16, address(0x1));

        doBorrow(0, getAsset(0), 5 * 10 ** 16);

        doBorrow(0, getAsset(2), 4 * 10 ** 16, address(0x1));
    }

    function testRDNativeB_Fail() public {
        // Should fail because the price of the borrow asset is a little too high

        address user = address(this);

        deal(getAssetAddress(0), address(0x1), 6 * 10 ** 16);
        uint256 userInitBalance = 105 * 10 ** 18;
        vm.deal(user, userInitBalance);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 5 * 10 ** 16);

        doDeposit(0, getAsset(0), 6 * 10 ** 16, address(0x1));

        doBorrowRevert(0, getAsset(0), 6 * 10 ** 16, "Vault is undercollateralized if this borrow goes through");
    }

    function testRDNativeBPW() public {
        address user = address(this);

        deal(getAssetAddress(0), user, 6 * 10 ** 16);
        uint256 userInitBalance = 105 * 10 ** 18;
        vm.deal(user, userInitBalance);
        vm.deal(address(0x1), userInitBalance);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 5 * 10 ** 16, address(0x1));

        doDeposit(0, getAsset(0), 6 * 10 ** 16);

        doBorrow(0, getAsset(2), 4 * 10 ** 16);

        doRepayNative(0, 3 * 10 ** 16);

        doWithdraw(0, getAsset(0), 4 * 10 ** 16);
    }

    function testRDNativeBPW_Fail() public {
        // Should fail because still some debt out so cannot withdraw all your deposited assets
        address user = address(this);

        deal(getAssetAddress(0), user, 6 * 10 ** 16);
        uint256 userInitBalance = 105 * 10 ** 18;
        vm.deal(user, userInitBalance);
        vm.deal(address(0x1), userInitBalance);

        doRegisterAsset(0, getAsset(0));
        doRegisterAsset(0, getAsset(2));

        doRegisterSpoke(0);

        setPrice(getAsset(0), 80);
        setPrice(getAsset(2), 90);

        doDepositNative(0, 5 * 10 ** 16, address(0x1));

        doDeposit(0, getAsset(0), 6 * 10 ** 16);

        doBorrow(0, getAsset(2), 4 * 10 ** 16);

        doRepayNative(0, 2 * 10 ** 16);

        doWithdrawRevert(0, getAsset(0), 4 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");
    }



    // test register SPOKE (make sure nothing is possible without doing this)

    /*
    // test register asset
    function testR_FS() public {
        doRegisterAsset_FS(getAsset(0));
    }

    function testRD_FS() public {
        deal(getAssetAddress(0), msg.sender, 5 * 10 ** 18);
        doRegisterAsset_FS(getAsset(0));
        doDeposit_FS(msg.sender, getAsset(0), 5 * 10 ** 18);
    }

    function testD_Fail_FS() public {
        // Should fail because there is no registered asset
        deal(getAssetAddress(0), msg.sender, 502 * 10 ** 18);
        doDeposit_FS(msg.sender, getAsset(0), 502 * 10 ** 18, "Unregistered asset");
    }

    function testRDB_FS() public {
        deal(getAssetAddress(0), msg.sender, 500 * 10 ** 18);
        deal(getAssetAddress(1), address(0x1), 600 * 10 ** 18);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        doRegisterSpoke_FS();

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit_FS(msg.sender, getAsset(0), 500 * 10 ** 18);
        doDeposit_FS(address(0x1), getAsset(1), 600 * 10 ** 18);

        doBorrow_FS(msg.sender, getAsset(1), 500 * 10 ** 18);
    }

    function testRDB_Fail_FS() public {
        // Should fail because the price of the borrow asset is a little too high

        deal(getAssetAddress(0), msg.sender, 5 * 10 ** 18);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 91);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, getAsset(0), 5 * 10 ** 18);
        doDeposit_FS(address(0x1), getAsset(1), 6 * 10 ** 18);

        doBorrow_FS(msg.sender, getAsset(1), 5 * 10 ** 18, "Vault is undercollateralized if this borrow goes through");
    }

    function testRDBW_FS() public {
        deal(getAssetAddress(0), msg.sender, 5 * 10 ** 18);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        doRegisterSpoke_FS();

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit_FS(msg.sender, getAsset(0), 5 * 10 ** 18);
        doDeposit_FS(address(0x1), getAsset(1), 6 * 10 ** 18);

        doBorrow_FS(msg.sender, getAsset(1), 5 * 10 ** 18);

        doWithdraw_FS(msg.sender, getAsset(0), 5 * 10 ** 16);
    }

    function testRDBW_Fail_FS() public {
        deal(getAssetAddress(0), msg.sender, 5 * 10 ** 18);
        deal(getAssetAddress(1), address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        doRegisterSpoke_FS();

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doDeposit_FS(msg.sender, getAsset(0), 5 * 10 ** 18);
        doDeposit_FS(address(0x1), getAsset(1), 6 * 10 ** 18);

        doBorrow_FS(msg.sender, getAsset(1), 5 * 10 ** 18);

        doWithdraw_FS(
            msg.sender,
            getAsset(0),
            5 * 10 ** 16 + 1 * 10 ** 14,
            "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBPW_FS() public {
        deal(getAssetAddress(0), msg.sender, 500 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 600 * 10 ** 16);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, getAsset(0), 500 * 10 ** 16);
        doDeposit_FS(address(0x1), getAsset(1), 600 * 10 ** 16);

        doBorrow_FS(msg.sender, getAsset(1), 500 * 10 ** 16);

        doRepay_FS(msg.sender, getAsset(1), 500 * 10 ** 16);

        doWithdraw_FS(msg.sender, getAsset(0), 500 * 10 ** 16);
    }

    function testRDBPW_Fail_FS() public {
        // Should fail because still some debt out so cannot withdraw all your deposited assets
        deal(getAssetAddress(0), msg.sender, 500 * 10 ** 16);
        deal(getAssetAddress(1), address(0x1), 600 * 10 ** 16);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, getAsset(0), 500 * 10 ** 16);
        doDeposit_FS(address(0x1), getAsset(1), 600 * 10 ** 16);

        doBorrow_FS(msg.sender, getAsset(1), 500 * 10 ** 16);

        doRepay_FS(msg.sender, getAsset(1), 500 * 10 ** 16 - 1 * 10 ** 10);

        doWithdraw_FS(
            msg.sender, getAsset(0), 500 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBL_Fail_FS() public {
        // should fail because vault not underwater
        deal(getAssetAddress(0), msg.sender, 501 * 10 ** 18);
        deal(getAssetAddress(1), msg.sender, 1100 * 10 ** 18);
        deal(getAssetAddress(0), address(0x1), 500 * 10 ** 18);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke_FS();

        doDeposit_FS(address(0x1), getAsset(0), 500 * 10 ** 18);
        doDeposit_FS(msg.sender, getAsset(1), 600 * 10 ** 18);

        doBorrow_FS(address(0x1), getAsset(1), 500 * 10 ** 18);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = getAssetAddress(1);
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;
        vm.prank(msg.sender);
        vm.expectRevert(bytes("vault not underwater"));
        getHub().liquidation(
            address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );
    }

    function testRDBL_FS() public {
        address vault = msg.sender;
        address vaultOther = address(0x1);

        // prank mint with tokens
        deal(getAssetAddress(0), vault, 1000 * 10 ** 20);
        deal(getAssetAddress(1), vault, 2000 * 10 ** 20);
        deal(getAssetAddress(0), vaultOther, 3000 * 10 ** 20);
        deal(getAssetAddress(1), vaultOther, 4000 * 10 ** 20);

        doRegisterAsset_FS(getAsset(0));
        doRegisterAsset_FS(getAsset(1));

        setPrice(getAsset(0), 100);
        setPrice(getAsset(1), 90);

        doRegisterSpoke_FS();

        doDeposit_FS(vaultOther, getAsset(0), 500 * 10 ** 18);
        doDeposit_FS(vault, getAsset(1), 600 * 10 ** 18);

        doBorrow_FS(vaultOther, getAsset(1), 500 * 10 ** 18);

        // move the price up for borrowed asset
        setPrice(getAsset(1), 95);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = getAssetAddress(1);
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = getAssetAddress(0);
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 490 * 10 ** 18;

        // prank approve contract to spend tokens
        vm.prank(vault);
        IERC20(getAssetAddress(1)).approve(address(getHub()), 500 * 10 ** 18);
        // uint256 allowanceAmount = IERC20(getAssetAddress(1)).allowance(vault, address(getHub()));

        // get vault token balances pre liquidation
        uint256 balance_vault_0_pre = IERC20(getAssetAddress(0)).balanceOf(vault);
        uint256 balance_vault_1_pre = IERC20(getAssetAddress(1)).balanceOf(vault);
        // get hub contract token balances pre liquidation
        uint256 balance_hub_0_pre = IERC20(getAssetAddress(0)).balanceOf(address(getHub()));
        uint256 balance_hub_1_pre = IERC20(getAssetAddress(1)).balanceOf(address(getHub()));

        vm.prank(vault);
        getHub().liquidation(vaultOther, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // get vault token balances post liquidation
        uint256 balance_vault_0_post = IERC20(getAssetAddress(0)).balanceOf(vault);
        uint256 balance_vault_1_post = IERC20(getAssetAddress(1)).balanceOf(vault);
        // get hub contract token balances post liquidation
        uint256 balance_hub_0_post = IERC20(getAssetAddress(0)).balanceOf(address(getHub()));
        uint256 balance_hub_1_post = IERC20(getAssetAddress(1)).balanceOf(address(getHub()));

        //console.log("balance of vault for token 0 went from ", balance_vault_0_pre, " to ", balance_vault_0_post);
        //console.log("balance of vault for token 1 went from ", balance_vault_1_pre, " to ", balance_vault_1_post);
        //console.log("balance of hub for token 0 went from ", balance_hub_0_pre, " to ", balance_hub_0_post);
        //console.log("balance of hub for token 1 went from ", balance_hub_1_pre, " to ", balance_hub_1_post);

        require(
            balance_vault_0_pre + balance_hub_0_pre == balance_vault_0_post + balance_hub_0_post,
            "Asset 0 total amounts should not change after liquidation"
        );
        require(
            balance_vault_1_pre + balance_hub_1_pre == balance_vault_1_post + balance_hub_1_post,
            "Asset 1 total amounts should not change after liquidation"
        );
    }
    */

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
