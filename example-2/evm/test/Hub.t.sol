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
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../src/interfaces/ITokenImplementation.sol";

import "../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./helpers/WormholeSimulator.sol";

import {TestHelpers} from "./helpers/TestHelpers.sol";

import {Spoke} from "../src/contracts/lendingSpoke/Spoke.sol";

import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

contract HubTest is Test, HubStructs, HubMessages, HubGetters, HubUtilities, TestHelpers {
    using BytesLib for bytes;

    // TODO: Decide what data goes where.. what makes sense here?

    TestAsset[] assets;
    Hub hub;

    // action codes
    // register: R
    // deposit: D
    // borrow: B
    // withdraw: W
    // repay: P
    // liquidation: L
    // fake spoke: FS

    function setUp() public {
        hub = testSetUp(vm);

        assets.push(
            TestAsset({
                assetAddress: 0x8b82A291F83ca07Af22120ABa21632088fC92931, // WETH
                asset: IERC20(0x8b82A291F83ca07Af22120ABa21632088fC92931),
                collateralizationRatioDeposit: 100 * 10 ** 16,
                collateralizationRatioBorrow: 110 * 10 ** 16,
                decimals: 18,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_AVAX_bnb") // bytes32("BNB")
            })
        );

        assets.push(
            TestAsset({
                assetAddress: 0x442F7f22b1EE2c842bEAFf52880d4573E9201158, // WBNB
                asset: IERC20(0x442F7f22b1EE2c842bEAFf52880d4573E9201158),
                collateralizationRatioDeposit: 100 * 10 ** 16,
                collateralizationRatioBorrow: 110 * 10 ** 16,
                decimals: 18,
                reserveFactor: 0,
                pythId: vm.envBytes32("PYTH_PRICE_FEED_AVAX_sol") // bytes32("SOL")
            })
        );

        int64 startPrice = 0;
        uint64 startConf = 0;
        int32 startExpo = 0;
        int64 startEmaPrice = 0;
        uint64 startEmaConf = 0;
        uint64 startPublishTime = 1;
        for (uint256 i = 0; i < assets.length; i++) {
            hub.setMockPythFeed(
                assets[i].pythId, startPrice, startConf, startExpo, startEmaPrice, startEmaConf, startPublishTime
            );
        }

        addSpoke(
            uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")),
            vm.envAddress("TESTING_WORMHOLE_ADDRESS_AVAX"),
            vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")
        );
        setSpokeData(0);
    }

    function testR() public {
        doRegisterSpoke(0);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);
    }

    function testD_Fail() public {
        doRegisterSpoke(0);

        doDepositRevert(0, assets[0], 0, "Unregistered asset");
    }

    function testRD() public {
        doRegisterSpoke(0);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        deal(assets[1].assetAddress, address(this), 1 * 10 ** 17);
        deal(assets[0].assetAddress, address(this), 5 * (10 ** 16));

        doDeposit(0, assets[1], 1 * 10 ** 17);
        doDeposit(0, assets[0], 5 * (10 ** 16));
    }

    function testRDB() public {
        deal(assets[0].assetAddress, address(this), 500 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 18);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        doRegisterSpoke(0);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit(0, assets[0], 500 * 10 ** 18);

        doDeposit(0, assets[1], 600 * 10 ** 18, address(0x1));

        doBorrow(0, assets[1], 500 * 10 ** 18);
    }

    function testRDB_Fail() public {
        // Should fail because the price of the borrow asset is a little too high

        deal(assets[0].assetAddress, address(this), 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 91);

        doRegisterSpoke(0);

        doDeposit(0, assets[0], 5 * 10 ** 18);

        doDeposit(0, assets[1], 6 * 10 ** 18, address(0x1));

        doBorrowRevert(0, assets[1], 5 * 10 ** 18, "Vault is undercollateralized if this borrow goes through");
    }

    function testRDBW() public {
        deal(assets[0].assetAddress, address(this), 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        doRegisterSpoke(0);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit(0, assets[0], 5 * 10 ** 18);

        doDeposit(0, assets[1], 6 * 10 ** 18, address(0x1));

        doBorrow(0, assets[1], 5 * 10 ** 18);

        doWithdraw(0, assets[0], 5 * 10 ** 16);
    }

    function testRDBW_Fail() public {
        deal(assets[0].assetAddress, address(this), 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        doRegisterSpoke(0);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit(0, assets[0], 5 * 10 ** 18);
        doDeposit(0, assets[1], 6 * 10 ** 18, address(0x1));

        doBorrow(0, assets[1], 5 * 10 ** 18);

        doWithdrawRevert(
            0, assets[0], 5 * 10 ** 16 + 1 * 10 ** 14, "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBPW() public {
        deal(assets[0].assetAddress, address(this), 500 * 10 ** 16);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 16);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke(0);

        doDeposit(0, assets[0], 500 * 10 ** 16);
        
        doDeposit(0, assets[1], 600 * 10 ** 16, address(0x1));

        doBorrow(0, assets[1], 500 * 10 ** 16);

        doRepay(0, assets[1], 500 * 10 ** 16);

        doWithdraw(0, assets[0], 500 * 10 ** 16);
    }

    function testRDBPW_Fail() public {
        // Should fail because still some debt out so cannot withdraw all your deposited assets
        deal(assets[0].assetAddress, address(this), 500 * 10 ** 16);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 16);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke(0);

        doDeposit(0, assets[0], 500 * 10 ** 16);
     
        doDeposit(0, assets[1], 600 * 10 ** 16, address(0x1));

        doBorrow(0, assets[1], 500 * 10 ** 16);

        doRepay(0, assets[1], 500 * 10 ** 16 - 1 * 10 ** 10);

        doWithdrawRevert(0, assets[0], 500 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");
    }

    function testRDBL_Fail() public {
        // should fail because vault not underwater
        deal(assets[0].assetAddress, address(this), 501 * 10 ** 18);
        deal(assets[1].assetAddress, address(this), 1100 * 10 ** 18);
        deal(assets[0].assetAddress, address(0x1), 500 * 10 ** 18);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke(0);

        doDeposit(0, assets[0], 500 * 10 ** 18, address(0x1));

        doDeposit(0, assets[1], 600 * 10 ** 18);

        doBorrow(0, assets[1], 500 * 10 ** 18, address(0x1));

        // liquidation attempted by address(this)
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;

        vm.expectRevert(bytes("vault not underwater"));
        hub.liquidation(
            address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );
    }

    function testRDBL() public {
        address vault = address(this);
        address vaultOther = address(0x1);

        // prank mint with tokens
        deal(assets[0].assetAddress, vault, 1000 * 10 ** 20);
        deal(assets[1].assetAddress, vault, 2000 * 10 ** 20);
        deal(assets[0].assetAddress, vaultOther, 3000 * 10 ** 20);
        deal(assets[1].assetAddress, vaultOther, 4000 * 10 ** 20);

        doRegisterAsset(0, assets[0]);
        doRegisterAsset(0, assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke(0);

        doDeposit(0, assets[0], 500 * 10 ** 18, vaultOther);
        doDeposit(0, assets[1], 600 * 10 ** 18);
        doBorrow(0, assets[1], 500 * 10 ** 18, vaultOther);

        // move the price up for borrowed asset
        setPrice(assets[1], 95);

        // liquidation attempted by address(this)
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 490 * 10 ** 18;

        IERC20(assets[1].assetAddress).approve(address(hub), 500 * 10 ** 18);
        // uint256 allowanceAmount = IERC20(assets[1].assetAddress).allowance(vault, address(hub));

        // get vault token balances pre liquidation
        uint256 balance_vault_0_pre = IERC20(assets[0].assetAddress).balanceOf(vault);
        uint256 balance_vault_1_pre = IERC20(assets[1].assetAddress).balanceOf(vault);
        // get hub contract token balances pre liquidation
        uint256 balance_hub_0_pre = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_pre = IERC20(assets[1].assetAddress).balanceOf(address(hub));

        hub.liquidation(vaultOther, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // get vault token balances post liquidation
        uint256 balance_vault_0_post = IERC20(assets[0].assetAddress).balanceOf(vault);
        uint256 balance_vault_1_post = IERC20(assets[1].assetAddress).balanceOf(vault);
        // get hub contract token balances post liquidation
        uint256 balance_hub_0_post = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_post = IERC20(assets[1].assetAddress).balanceOf(address(hub));

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

    // test register SPOKE (make sure nothing is possible without doing this)

    // test register asset
    function testR_FS() public {
        doRegisterAsset_FS(assets[0]);
    }

    function testRD_FS() public {
        deal(assets[0].assetAddress, msg.sender, 5 * 10 ** 18);
        doRegisterAsset_FS(assets[0]);
        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 18);
    }

    function testD_Fail_FS() public {
        // Should fail because there is no registered asset
        deal(assets[0].assetAddress, msg.sender, 502 * 10 ** 18);
        doDeposit_FS(msg.sender, assets[0], 502 * 10 ** 18, "Unregistered asset");
    }

    function testRDB_FS() public {
        deal(assets[0].assetAddress, msg.sender, 500 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 18);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        doRegisterSpoke_FS();

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit_FS(msg.sender, assets[0], 500 * 10 ** 18);
        doDeposit_FS(address(0x1), assets[1], 600 * 10 ** 18);

        doBorrow_FS(msg.sender, assets[1], 500 * 10 ** 18);
    }

    function testRDB_Fail_FS() public {
        // Should fail because the price of the borrow asset is a little too high

        deal(assets[0].assetAddress, msg.sender, 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 91);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 18);
        doDeposit_FS(address(0x1), assets[1], 6 * 10 ** 18);

        doBorrow_FS(msg.sender, assets[1], 5 * 10 ** 18, "Vault is undercollateralized if this borrow goes through");
    }

    function testRDBW_FS() public {
        deal(assets[0].assetAddress, msg.sender, 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        doRegisterSpoke_FS();

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 18);
        doDeposit_FS(address(0x1), assets[1], 6 * 10 ** 18);

        doBorrow_FS(msg.sender, assets[1], 5 * 10 ** 18);

        doWithdraw_FS(msg.sender, assets[0], 5 * 10 ** 16);
    }

    function testRDBW_Fail_FS() public {
        deal(assets[0].assetAddress, msg.sender, 5 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 6 * 10 ** 18);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        doRegisterSpoke_FS();

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 18);
        doDeposit_FS(address(0x1), assets[1], 6 * 10 ** 18);

        doBorrow_FS(msg.sender, assets[1], 5 * 10 ** 18);

        doWithdraw_FS(
            msg.sender,
            assets[0],
            5 * 10 ** 16 + 1 * 10 ** 14,
            "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBPW_FS() public {
        deal(assets[0].assetAddress, msg.sender, 500 * 10 ** 16);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 16);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, assets[0], 500 * 10 ** 16);
        doDeposit_FS(address(0x1), assets[1], 600 * 10 ** 16);

        doBorrow_FS(msg.sender, assets[1], 500 * 10 ** 16);

        doRepay_FS(msg.sender, assets[1], 500 * 10 ** 16);

        doWithdraw_FS(msg.sender, assets[0], 500 * 10 ** 16);
    }

    function testRDBPW_Fail_FS() public {
        // Should fail because still some debt out so cannot withdraw all your deposited assets
        deal(assets[0].assetAddress, msg.sender, 500 * 10 ** 16);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 16);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, assets[0], 500 * 10 ** 16);
        doDeposit_FS(address(0x1), assets[1], 600 * 10 ** 16);

        doBorrow_FS(msg.sender, assets[1], 500 * 10 ** 16);

        doRepay_FS(msg.sender, assets[1], 500 * 10 ** 16 - 1 * 10 ** 10);

        doWithdraw_FS(
            msg.sender, assets[0], 500 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through"
        );
    }

    function testRDBL_Fail_FS() public {
        // should fail because vault not underwater
        deal(assets[0].assetAddress, msg.sender, 501 * 10 ** 18);
        deal(assets[1].assetAddress, msg.sender, 1100 * 10 ** 18);
        deal(assets[0].assetAddress, address(0x1), 500 * 10 ** 18);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(address(0x1), assets[0], 500 * 10 ** 18);
        doDeposit_FS(msg.sender, assets[1], 600 * 10 ** 18);

        doBorrow_FS(address(0x1), assets[1], 500 * 10 ** 18);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;
        vm.prank(msg.sender);
        vm.expectRevert(bytes("vault not underwater"));
        hub.liquidation(
            address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts
        );
    }

    function testRDBL_FS() public {
        address vault = msg.sender;
        address vaultOther = address(0x1);

        // prank mint with tokens
        deal(assets[0].assetAddress, vault, 1000 * 10 ** 20);
        deal(assets[1].assetAddress, vault, 2000 * 10 ** 20);
        deal(assets[0].assetAddress, vaultOther, 3000 * 10 ** 20);
        deal(assets[1].assetAddress, vaultOther, 4000 * 10 ** 20);

        doRegisterAsset_FS(assets[0]);
        doRegisterAsset_FS(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(vaultOther, assets[0], 500 * 10 ** 18);
        doDeposit_FS(vault, assets[1], 600 * 10 ** 18);

        doBorrow_FS(vaultOther, assets[1], 500 * 10 ** 18);

        // move the price up for borrowed asset
        setPrice(assets[1], 95);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10 ** 18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 490 * 10 ** 18;

        // prank approve contract to spend tokens
        vm.prank(vault);
        IERC20(assets[1].assetAddress).approve(address(hub), 500 * 10 ** 18);
        // uint256 allowanceAmount = IERC20(assets[1].assetAddress).allowance(vault, address(hub));

        // get vault token balances pre liquidation
        uint256 balance_vault_0_pre = IERC20(assets[0].assetAddress).balanceOf(vault);
        uint256 balance_vault_1_pre = IERC20(assets[1].assetAddress).balanceOf(vault);
        // get hub contract token balances pre liquidation
        uint256 balance_hub_0_pre = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_pre = IERC20(assets[1].assetAddress).balanceOf(address(hub));

        vm.prank(vault);
        hub.liquidation(vaultOther, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // get vault token balances post liquidation
        uint256 balance_vault_0_post = IERC20(assets[0].assetAddress).balanceOf(vault);
        uint256 balance_vault_1_post = IERC20(assets[1].assetAddress).balanceOf(vault);
        // get hub contract token balances post liquidation
        uint256 balance_hub_0_post = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_post = IERC20(assets[1].assetAddress).balanceOf(address(hub));

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
