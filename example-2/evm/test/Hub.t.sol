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
      Spoke[] spokes;

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
        for(uint i=0; i<assets.length; i++){
            hub.setMockPythFeed(assets[i].pythId, startPrice, startConf, startExpo, startEmaPrice, startEmaConf, startPublishTime);
        }

        addSpoke(uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), vm.envAddress("TESTING_WORMHOLE_ADDRESS_AVAX"), vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX"));
        setSpokeData(0);

    }

    function registerSpokesAndAssets() internal returns (Spoke[] memory) {
        
        spokes.push(doRegisterSpoke(0));

        bytes memory encodedMessage0 = doRegisterAsset(assets[0]);
        spokes[0].completeRegisterAsset(encodedMessage0);

        bytes memory encodedMessage1 = doRegisterAsset(assets[1]);
        spokes[0].completeRegisterAsset(encodedMessage1);

        return spokes;
    }

    function testR() public {
        registerSpokesAndAssets();
    }

    function testRD() public {

        registerSpokesAndAssets();

        address user = msg.sender;

        deal(assets[1].assetAddress, user, 1 * 10 ** 17);
        deal(assets[0].assetAddress, user, 5 * (10 ** 16));
        
        vm.prank(user);
        assets[1].asset.approve(address(spokes[0]), 1 * 10 ** 17);
        vm.prank(user);
        assets[0].asset.approve(address(spokes[0]), 5 * (10 ** 16));
   
        VaultAmount memory globalBefore = hub.getGlobalAmounts(assets[1].assetAddress);
        VaultAmount memory vaultBefore = hub.getVaultAmounts(user, assets[1].assetAddress);
       
        uint256 balance_user_0_pre = IERC20(assets[0].assetAddress).balanceOf(user);
        uint256 balance_user_1_pre = IERC20(assets[1].assetAddress).balanceOf(user);
        uint256 balance_hub_0_pre = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_pre = IERC20(assets[1].assetAddress).balanceOf(address(hub));

        vm.prank(user);
        bytes memory encodedDepositMessage = doDeposit(0, assets[1], 1 * 10 ** 17);
        vm.prank(user);
        bytes memory encodedDepositMessage2 = doDeposit(0, assets[0], 5 * (10 ** 16));

        hub.completeDeposit(encodedDepositMessage);
        hub.completeDeposit(encodedDepositMessage2);

        uint256 balance_user_0_post = IERC20(assets[0].assetAddress).balanceOf(user);
        uint256 balance_user_1_post = IERC20(assets[1].assetAddress).balanceOf(user);
    
        uint256 balance_hub_0_post = IERC20(assets[0].assetAddress).balanceOf(address(hub));
        uint256 balance_hub_1_post = IERC20(assets[1].assetAddress).balanceOf(address(hub));

        VaultAmount memory globalAfter = hub.getGlobalAmounts(assets[1].assetAddress);
        VaultAmount memory vaultAfter = hub.getVaultAmounts(user, assets[1].assetAddress);
        
        require(globalBefore.deposited == 0, "Deposited not initialized to 0");
        require(globalAfter.deposited == 1 * 10 ** 17 , "1 * 10 ** 17 wasn't deposited (globally)");

        require(vaultBefore.deposited == 0, "Deposited not initialized to 0");
        require(vaultAfter.deposited == 1 * 10 ** 17, "1 * 10 ** 17 wasn't deposited (in the vault)");

        require(balance_user_1_pre == 1 * 10 ** 17, "User asset 1 balance not 1 * 10^17 initially");
        require(balance_user_0_pre == 5 * (10 ** 16) , "User asset 0 balance not 5 * 10^16 initially");

        require(balance_hub_0_pre == 0, "Hub asset 0 balance not 0 initially");
        require(balance_hub_1_pre == 0, "Hub asset 1 balance not 0 initially");

        require(balance_user_0_post == 0, "User asset 0 balance not 0 after");
        require(balance_user_1_post == 0 , "User asset 1 balance not 0 after");

        require(balance_hub_1_post == 1 * 10 ** 17, "Hub asset 1 balance not 1 * 10 ** 17 after");
        require(balance_hub_0_post == 5 * (10 ** 16), "Hub asset 0 balance not 5 * 10^16 after");
    }

    // test register SPOKE (make sure nothing is possible without doing this)

    // test register asset
    function testR_FS() public {
        doRegisterAsset(assets[0]);        
    }


    function testRD_FS() public {
        deal(assets[0].assetAddress, msg.sender, 5 * 10 ** 10);
        doRegisterAsset(assets[0]);
        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 10);
    }

    function testD_Fail_FS() public {
        // Should fail because there is no registered asset
        deal(assets[0].assetAddress, msg.sender, 502 * 10 ** 12);
        doDeposit_FS(msg.sender, assets[0], 502 * 10 ** 12, "Unregistered asset");
    }

    function testRDB_FS() public {

        deal(assets[0].assetAddress, msg.sender, 500 * 10 ** 18);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 18);

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);

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

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);

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

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);

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

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);

        doRegisterSpoke_FS();


        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doDeposit_FS(msg.sender, assets[0], 5 * 10 ** 18);
        doDeposit_FS(address(0x1), assets[1], 6 * 10 ** 18);


        doBorrow_FS(msg.sender, assets[1], 5 * 10 ** 18);
    
        doWithdraw_FS(msg.sender, assets[0], 5 * 10 ** 16 + 1, "Vault is undercollateralized if this withdraw goes through");
    }

    function testRDBPW_FS() public {

        deal(assets[0].assetAddress, msg.sender, 500 * 10 ** 16);
        deal(assets[1].assetAddress, address(0x1), 600 * 10 ** 16);
       
        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);
        


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
       
        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);
        

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);
        
        doRegisterSpoke_FS();

        doDeposit_FS(msg.sender, assets[0], 500 * 10 ** 16);
        doDeposit_FS(address(0x1), assets[1], 600 * 10 ** 16);


        doBorrow_FS(msg.sender, assets[1], 500 * 10 ** 16);

        doRepay_FS(msg.sender, assets[1], 500 * 10 ** 16 - 1 * 10 ** 10);
    
        doWithdraw_FS(msg.sender, assets[0], 500 * 10 ** 16, "Vault is undercollateralized if this withdraw goes through");
    }

    function testRDBL_Fail_FS() public {
        // should fail because vault not underwater
        deal(assets[0].assetAddress, msg.sender, 501 * 10 ** 18);
        deal(assets[1].assetAddress, msg.sender, 1100 * 10 ** 18);
        deal(assets[0].assetAddress, address(0x1), 500 * 10 ** 18);

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);


        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(address(0x1), assets[0], 500 * 10**18);
        doDeposit_FS(msg.sender, assets[1], 600 * 10**18);
    
        doBorrow_FS(address(0x1), assets[1], 500 * 10**18);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10**18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 1;
        vm.prank(msg.sender);
        vm.expectRevert(bytes("vault not underwater"));
        hub.liquidation(address(0x1), assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);
    }

    function testRDBL_FS() public {

        address vault = msg.sender;
        address vaultOther = address(0x1);

        // prank mint with tokens
        deal(assets[0].assetAddress, vault, 1000 * 10**20);
        deal(assets[1].assetAddress, vault, 2000 * 10**20);
        deal(assets[0].assetAddress, vaultOther, 3000 * 10**20);
        deal(assets[1].assetAddress, vaultOther, 4000 * 10**20);

        doRegisterAsset(assets[0]);
        doRegisterAsset(assets[1]);

        setPrice(assets[0], 100);
        setPrice(assets[1], 90);

        doRegisterSpoke_FS();

        doDeposit_FS(vaultOther, assets[0], 500 * 10**18);
        doDeposit_FS(vault, assets[1], 600 * 10**18);
    
        doBorrow_FS(vaultOther, assets[1], 500 * 10**18);

        // move the price up for borrowed asset
        setPrice(assets[1], 95);

        // liquidation attempted by msg.sender
        address[] memory assetRepayAddresses = new address[](1);
        assetRepayAddresses[0] = assets[1].assetAddress;
        uint256[] memory assetRepayAmounts = new uint256[](1);
        assetRepayAmounts[0] = 500 * 10**18;
        address[] memory assetReceiptAddresses = new address[](1);
        assetReceiptAddresses[0] = assets[0].assetAddress;
        uint256[] memory assetReceiptAmounts = new uint256[](1);
        assetReceiptAmounts[0] = 490 * 10**18;

        // prank approve contract to spend tokens
        vm.prank(vault);
        IERC20(assets[1].assetAddress).approve(address(hub), 500 * 10**18);
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

        require(balance_vault_0_pre + balance_hub_0_pre == balance_vault_0_post + balance_hub_0_post, "Asset 0 total amounts should not change after liquidation");
        require(balance_vault_1_pre + balance_hub_1_pre == balance_vault_1_post + balance_hub_1_post, "Asset 1 total amounts should not change after liquidation");
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
