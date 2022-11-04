// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

import {Hub} from "../../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../../src/contracts/lendingHub/HubStructs.sol";
import {HubMessages} from "../../src/contracts/lendingHub/HubMessages.sol";
import {HubUtilities} from "../../src/contracts/lendingHub/HubUtilities.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {IWormhole} from "../../src/interfaces/IWormhole.sol";
import {ITokenBridge} from "../../src/interfaces/ITokenBridge.sol";
import {ITokenImplementation} from "../../src/interfaces/ITokenImplementation.sol";
import {Spoke} from "../../src/contracts/lendingSpoke/Spoke.sol";
import {TestStructs} from "./TestStructs.sol";
import {TestState} from "./TestState.sol";
import {TestSetters} from "./TestSetters.sol";
import {TestGetters} from "./TestGetters.sol";
import {TestUtilities} from "./TestUtilities.sol";

import "../../src/contracts/lendingHub/HubGetters.sol";

import {WormholeSimulator} from "./WormholeSimulator.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract TestHelpers is HubStructs, HubMessages, TestStructs, TestState, TestGetters, TestSetters, TestUtilities {
    
    using BytesLib for bytes;


    function testSetUp() internal {

        Vm vm = getVm();
        // this will be used to sign wormhole messages
        uint256 guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        WormholeSimulator wormholeSimulator =
            new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS_AVAX"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        IWormhole wormholeContract = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormholeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), "wrong chainId");
        require(wormholeContract.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE_AVAX"), "wrong messageFee");
        require(
            wormholeContract.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX_AVAX")),
            "wrong guardian set index"
        );

        // set up Token Bridge
        ITokenBridge tokenBridgeContract = ITokenBridge(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX"));

        // verify Token Bridge state from fork
        require(tokenBridgeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), "wrong chainId");
        

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        uint256 interestAccrualIndexPrecision = 10 ** 18;
        uint256 collateralizationRatioPrecision = 10 ** 18;
        uint8 initialMaxDecimals = 24;
        uint256 maxLiquidationBonus = 105 * 10**16;
        uint256 maxLiquidationPortion = 100;
        uint256 maxLiquidationPortionPrecision = 100;
        uint8 oracleMode = 1;
        uint64 nConf = 424;
        uint64 nConfPrecision = 100;
        address pythAddress = vm.envAddress("TESTING_PYTH_ADDRESS_AVAX");

        Hub hub =
        new Hub(
            address(wormholeContract), 
            address(tokenBridgeContract), 
            pythAddress, 
            oracleMode,
            wormholeFinality, 
            interestAccrualIndexPrecision, 
            collateralizationRatioPrecision, 
            initialMaxDecimals, 
            maxLiquidationBonus, 
            maxLiquidationPortion, 
            maxLiquidationPortionPrecision,
            nConf,
            nConfPrecision
        );

        setHubData(HubData({
            guardianSigner: guardianSigner,
            wormholeSimulator: wormholeSimulator,
            wormholeContract: wormholeContract,
            tokenBridgeContract: tokenBridgeContract,
            hub: hub,
            hubChainId: wormholeContract.chainId()
        }));

        setVm(vm);

        setPublishTime(1);
        
        registerChainOnHub(6, bytes32(uint256(uint160(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS_AVAX")))));

    }

    function doRegisterSpoke(uint256 index) internal returns (Spoke) {

        SpokeData memory spokeData = getSpokeData(index);
        // register asset
        getHub().registerSpoke(
            spokeData.foreignChainId, address(spokeData.spoke)
        );

        return spokeData.spoke;
    }

    function doRegisterAsset(uint256 spokeIndex, Asset memory asset) internal {
        Vm vm = getVm();
        
        uint256 reservePrecision = 1 * 10**18;
        
        // register asset
        vm.recordLogs();
        getHub().registerAsset(
            asset.assetAddress, asset.collateralizationRatioDeposit, asset.collateralizationRatioBorrow, asset.reserveFactor, reservePrecision, asset.pythId, asset.decimals
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(spokeIndex, entries[entries.length - 1]);

        getSpoke(spokeIndex).completeRegisterAsset(encodedMessage);

        AssetInfo memory info = getHub().getAssetInfo(asset.assetAddress);

        require(
            (info.collateralizationRatioDeposit == asset.collateralizationRatioDeposit) && (info.collateralizationRatioBorrow == asset.collateralizationRatioBorrow) && (info.decimals == asset.decimals) && (info.pythId == asset.pythId) && (info.exists) && (info.interestRateModel.ratePrecision == 1 * 10 ** 18) && (info.interestRateModel.rateIntercept == 0) && (info.interestRateModel.rateCoefficientA == 0) && (info.interestRateModel.reserveFactor == asset.reserveFactor) && (info.interestRateModel.reservePrecision == reservePrecision),
            "didn't register properly" 
        );
    }

    function doDeposit(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doDeposit(spokeIndex, asset.assetAddress, assetAmount, false, "", false, address(0x0));
    }
    function doDeposit(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doDeposit(spokeIndex, asset.assetAddress, assetAmount, false, "", true, vault);
    }
    function doDepositRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doDeposit(spokeIndex, asset.assetAddress, assetAmount, true, revertString, false, address(0x0));
    }
    function doDeposit(uint256 spokeIndex, address assetAddress, uint256 assetAmount, bool expectRevert, string memory revertString, bool prankVault, address fakeVault) internal {
        Spoke spoke = getSpoke(spokeIndex);
        Vm vm = getVm();

        address vault = address(this);
        if(prankVault) vault = fakeVault;

        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(vault);

        if(prankVault) {
            vm.prank(vault);
        }
        IERC20(assetAddress).approve(address(spoke), assetAmount);

        if(prankVault) {
            vm.prank(vault);
        }
        vm.recordLogs();
        spoke.depositCollateral(assetAddress, assetAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(spokeIndex, entries[entries.length - 1]);

        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeDeposit(encodedMessage);

        if(expectRevert) {
            return;
        }

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(vault);
        require(globalAfter.deposited - globalBefore.deposited == assetAmount, "Amount wasn't deposited globally");
        require(vaultAfter.deposited - vaultBefore.deposited == assetAmount, "Amount wasn't deposited in vault");
        require(balanceAfter - balanceBefore == assetAmount, "Amount wasn't transferred to hub");
        require(balanceUserBefore - balanceUserAfter == assetAmount, "Amount wasn't transferred from user");
    }

    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doRepay(spokeIndex, asset.assetAddress, assetAmount, false, "", false, address(0x0));
    }
    function doRepay(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doRepay(spokeIndex, asset.assetAddress, assetAmount, false, "", true, vault);
    }
    function doRepayRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doRepay(spokeIndex, asset.assetAddress, assetAmount, true, revertString, false, address(0x0));
    }
    function doRepay(uint256 spokeIndex, address assetAddress, uint256 assetAmount, bool expectRevert, string memory revertString, bool prankVault, address fakeVault) internal {
        Spoke spoke = getSpoke(spokeIndex);
        Vm vm = getVm();
        address vault = address(this);
        if(prankVault) vault = fakeVault;

        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(vault);

        if(prankVault) {
            vm.prank(vault);
        }
        IERC20(assetAddress).approve(address(spoke), assetAmount);

        if(prankVault) {
            vm.prank(vault);
        }
        vm.recordLogs();
        spoke.repay(assetAddress, assetAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(spokeIndex, entries[entries.length - 1]);

        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeRepay(encodedMessage);

        if(expectRevert) {
            return;
        }

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(vault);
        require(globalBefore.borrowed - globalAfter.borrowed == assetAmount, "Amount wasn't repayed globally");
        require(vaultBefore.borrowed - vaultAfter.borrowed == assetAmount, "Amount wasn't repayed in vault");
        require(balanceAfter - balanceBefore == assetAmount, "Amount wasn't transferred to hub");
        require(balanceUserBefore - balanceUserAfter == assetAmount, "Amount wasn't transferred from user");
    }

    function doBorrow(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doBorrow(spokeIndex, asset.assetAddress, assetAmount, false, "", false, address(0x0));
    }
    function doBorrow(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doBorrow(spokeIndex, asset.assetAddress, assetAmount, false, "", true, vault);
    }
    function doBorrowRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doBorrow(spokeIndex, asset.assetAddress, assetAmount, true, revertString, false, address(0x0));
    }
    
    function doBorrow(uint256 spokeIndex, address assetAddress, uint256 assetAmount, bool expectRevert, string memory revertString, bool prankVault, address fakeVault) internal {
        Spoke spoke = getSpoke(spokeIndex);
        Vm vm = getVm();
        address vault = address(this);
        if(prankVault) vault = fakeVault;

        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(vault);

        if(prankVault) {
            vm.prank(vault);
        }
        IERC20(assetAddress).approve(address(spoke), assetAmount);

        if(prankVault) {
            vm.prank(vault);
        }
        vm.recordLogs();
        spoke.borrow(assetAddress, assetAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(spokeIndex, entries[entries.length - 1]);
   
        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeBorrow(encodedMessage);

        if(expectRevert) {
            return;
        }

        entries = vm.getRecordedLogs();
        encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        

        require(globalAfter.borrowed - globalBefore.borrowed == assetAmount, "Amount wasn't borrowed globally");
        require(vaultAfter.borrowed - vaultBefore.borrowed == assetAmount, "Amount wasn't borrowed in vault");
        require(balanceBefore - balanceAfter == assetAmount, "Amount wasn't transferred from hub");

        getHubData().tokenBridgeContract.completeTransfer(encodedMessage);


        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(vault);

        require(balanceUserAfter - balanceUserBefore == assetAmount, "Amount wasn't transferred to user");
    }

    function doWithdraw(uint256 spokeIndex, Asset memory asset, uint256 assetAmount) internal {
        doWithdraw(spokeIndex, asset.assetAddress, assetAmount, false, "", false, address(0x0));
    }
    function doWithdrawRevert(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, string memory revertString) internal {
        doWithdraw(spokeIndex, asset.assetAddress, assetAmount, true, revertString, false, address(0x0));
    }
    function doWithdraw(uint256 spokeIndex, Asset memory asset, uint256 assetAmount, address vault) internal {
        doWithdraw(spokeIndex, asset.assetAddress, assetAmount, false, "", true, vault);
    }
    function doWithdraw(uint256 spokeIndex, address assetAddress, uint256 assetAmount, bool expectRevert, string memory revertString, bool prankVault, address fakeVault) internal {
        Spoke spoke = getSpoke(spokeIndex);
        Vm vm = getVm();    
        address vault = address(this);
        if(prankVault) vault = fakeVault;

        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(vault);

        if(prankVault) {
            vm.prank(vault);
        }
        IERC20(assetAddress).approve(address(spoke), assetAmount);

        if(prankVault) {
            vm.prank(vault);
        }
        vm.recordLogs();
        spoke.withdrawCollateral(assetAddress, assetAmount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromSpokeLogs(spokeIndex, entries[entries.length - 1]);

        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeWithdraw(encodedMessage);

        if(expectRevert) {
            return;
        }

        entries = vm.getRecordedLogs();
        encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        

        require(globalBefore.deposited - globalAfter.deposited == assetAmount, "Amount wasn't withdrawn globally");
        require(vaultBefore.deposited - vaultAfter.deposited == assetAmount, "Amount wasn't withdrawn in vault");
        require(balanceBefore - balanceAfter == assetAmount, "Amount wasn't transferred from hub");

        getHubData().tokenBridgeContract.completeTransfer(encodedMessage);

        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(vault);
        require(balanceUserAfter - balanceUserBefore == assetAmount, "Amount wasn't transferred to user");
    }


    function doRegisterSpoke_FS() internal {
        // register asset
        Vm vm = getVm();
        getHub().registerSpoke(
            uint16(vm.envUint("TESTING_WORMHOLE_CHAINID_AVAX")), address(this)
            //2, address(0x1)
        );
    }

    function doRegisterAsset_FS(Asset memory asset) internal {
        uint256 reservePrecision = 1 * 10**18;

        // register asset
        getHub().registerAsset(
            asset.assetAddress, asset.collateralizationRatioDeposit, asset.collateralizationRatioBorrow, asset.reserveFactor, reservePrecision, asset.pythId, asset.decimals
        );
        AssetInfo memory info = getHub().getAssetInfo(asset.assetAddress);

        require(
            (info.collateralizationRatioDeposit == asset.collateralizationRatioDeposit) && (info.collateralizationRatioBorrow == asset.collateralizationRatioBorrow) && (info.decimals == asset.decimals) && (info.pythId == asset.pythId) && (info.exists) && (info.interestRateModel.ratePrecision == 1 * 10 ** 18) && (info.interestRateModel.rateIntercept == 0) && (info.interestRateModel.rateCoefficientA == 0) && (info.interestRateModel.reserveFactor == asset.reserveFactor) && (info.interestRateModel.reservePrecision == reservePrecision),
            "didn't register properly" 
        );
    }


    function doDeposit_FS(address vault, Asset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doDeposit_FS(vault, asset, assetAmount, false, "");
    }

    function doDeposit_FS(address vault, Asset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doDeposit_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doDeposit_FS(address vault, Asset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
    {
        address assetAddress = asset.assetAddress;
        Vm vm = getVm();
        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(address(vault));

        vm.prank(vault);
        IERC20(assetAddress).transfer(address(getHubData().tokenBridgeContract), assetAmount);

        // create Deposit payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        DepositPayload memory myPayload =
            DepositPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeDepositPayload(myPayload);
      
        // get wrapped info
        ITokenImplementation wrapped = getWrappedInfo(assetAddress);
    

        // TokenBridgePayload
        ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
            payloadID: 3,
            amount: normalizeAmountWithinTokenBridge(assetAmount, asset.decimals),
            tokenAddress: wrapped.nativeContract(),
            tokenChain: wrapped.chainId(),
            to: bytes32(uint256(uint160(address(getHub())))),
            toChain: getHubData().wormholeContract.chainId(),
            fromAddress: bytes32(uint256(uint160(vault))),
            payload: serialized
        });
     
        bytes memory encodedVM = getSignedWHMsgTransferTokenBridge(transfer);
       
        // complete deposit
        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeDeposit(encodedVM);

        if(expectRevert) {
            return;
        }

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(address(vault));
        require(globalAfter.deposited - globalBefore.deposited == assetAmount, "Amount wasn't deposited globally");
        require(vaultAfter.deposited - vaultBefore.deposited == assetAmount, "Amount wasn't deposited in vault");
        require(balanceAfter - balanceBefore == assetAmount, "Amount wasn't transferred to hub");
        require(balanceUserBefore - balanceUserAfter == assetAmount, "Amount wasn't transferred from user");
        
    }

    function doRepay_FS(address vault, Asset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doRepay_FS(vault, asset, assetAmount, false, "");
    }

    function doRepay_FS(address vault, Asset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doRepay_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doRepay_FS(address vault, Asset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
    {
        address assetAddress = asset.assetAddress;
        Vm vm = getVm();
        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(address(vault));

        vm.prank(vault);
        IERC20(assetAddress).transfer(address(getHubData().tokenBridgeContract), assetAmount);

        // create Repay payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(4),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        RepayPayload memory myPayload =
            RepayPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeRepayPayload(myPayload);

        // get wrapped info
        ITokenImplementation wrapped = getWrappedInfo(assetAddress);


        // TokenBridgePayload
        ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
            payloadID: 3,
            amount: normalizeAmountWithinTokenBridge(assetAmount, asset.decimals),
            tokenAddress: wrapped.nativeContract(),
            tokenChain: wrapped.chainId(),
            to: bytes32(uint256(uint160(address(getHub())))),
            toChain: getHubData().wormholeContract.chainId(),
            fromAddress: bytes32(uint256(uint160(vault))),
            payload: serialized
        });

        bytes memory encodedVM = getSignedWHMsgTransferTokenBridge(transfer);

        // complete repay
        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeRepay(encodedVM);

        if(expectRevert) {
            return;
        }

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(address(vault));
        require(globalBefore.borrowed - globalAfter.borrowed == assetAmount, "Amount wasn't repayed globally");
        require(vaultBefore.borrowed - vaultAfter.borrowed == assetAmount, "Amount wasn't repayed in vault");
        require(balanceAfter - balanceBefore == assetAmount, "Amount wasn't transferred to hub");
        require(balanceUserBefore - balanceUserAfter == assetAmount, "Amount wasn't transferred from user");
    }

    function doBorrow_FS(address vault, Asset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doBorrow_FS(vault, asset, assetAmount, false, "");
    }

    function doBorrow_FS(address vault, Asset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doBorrow_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Borrow payload and package it into TokenBridgePayload into WH message and send the borrow
    function doBorrow_FS(address vault, Asset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal
    {
        address assetAddress = asset.assetAddress;
        Vm vm = getVm();
        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(vault);

        // create Borrow payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(3),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        BorrowPayload memory myPayload =
            BorrowPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeBorrowPayload(myPayload);

        bytes memory encodedVM = getSignedWHMsgCoreBridge(serialized);

        // complete borrow
       vm.recordLogs();
      
        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }
        getHub().completeBorrow(encodedVM);

        if(expectRevert) {
            return;
        }

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));
        

        require(globalAfter.borrowed - globalBefore.borrowed == assetAmount, "Amount wasn't borrowed globally");
        require(vaultAfter.borrowed - vaultBefore.borrowed == assetAmount, "Amount wasn't borrowed in vault");
        require(balanceBefore - balanceAfter == assetAmount, "Amount wasn't transferred from hub");

        vm.prank(vault);
        getHubData().tokenBridgeContract.completeTransfer(encodedMessage);

        
        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(vault);

        require(balanceUserAfter - balanceUserBefore == assetAmount, "Amount wasn't transferred to user");
    }

    function doWithdraw_FS(address vault, Asset memory asset, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        doWithdraw_FS(vault, asset, assetAmount, false, "");
    }

    function doWithdraw_FS(address vault, Asset memory asset, uint256 assetAmount, string memory revertString) internal returns (bytes memory encodedVM) {
        doWithdraw_FS(vault, asset, assetAmount, true, revertString);
    }

    // create Withdraw payload and package it into TokenBridgePayload into WH message and send the withdraw
    function doWithdraw_FS(address vault, Asset memory asset, uint256 assetAmount, bool expectRevert, string memory revertString)
        internal {
        Vm vm = getVm();
        address assetAddress = asset.assetAddress;
        requireAssetAmountValidForTokenBridge(assetAddress, assetAmount);
        VaultAmount memory globalBefore = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultBefore = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceBefore = IERC20(assetAddress).balanceOf(address(getHub()));
        uint256 balanceUserBefore = IERC20(assetAddress).balanceOf(address(vault));

        // create Withdraw payload
        PayloadHeader memory header = PayloadHeader({payloadID: uint8(2), sender: vault});
        WithdrawPayload memory myPayload =
            WithdrawPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeWithdrawPayload(myPayload);

        bytes memory encodedVM = getSignedWHMsgCoreBridge(serialized);


        vm.recordLogs();
        // complete withdraw
        if(expectRevert) {
            vm.expectRevert(bytes(revertString));
        }

        getHub().completeWithdraw(encodedVM);

        if(expectRevert) {
            return;
        }

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory encodedMessage = fetchSignedMessageFromHubLogs(entries[entries.length - 1]);

        VaultAmount memory globalAfter = getHub().getGlobalAmounts(assetAddress);
        VaultAmount memory vaultAfter = getHub().getVaultAmounts(vault, assetAddress);
        uint256 balanceAfter = IERC20(assetAddress).balanceOf(address(getHub()));

        require(globalBefore.deposited - globalAfter.deposited == assetAmount, "Amount wasn't withdrawn globally");
        require(vaultBefore.deposited - vaultAfter.deposited == assetAmount, "Amount wasn't withdrawn in vault");
        require(balanceBefore - balanceAfter == assetAmount, "Amount wasn't transferred from hub");

        vm.prank(vault);
        getHubData().tokenBridgeContract.completeTransfer(encodedMessage);

        uint256 balanceUserAfter = IERC20(assetAddress).balanceOf(address(vault));
        require(balanceUserAfter - balanceUserBefore == assetAmount, "Amount wasn't transferred to user");
    }

    function setPrice(Asset memory asset, int64 price) internal {
       setPrice(asset, price, 0, 0, 100, 100);
    }

    function setPrice(Asset memory asset, int64 price, uint64 conf, int32 expo, int64 emaPrice, uint64 emaConf) internal {
        // TODO: Double check publish time is correct

        uint64 publishTime = getPublishTime();
        publishTime += 1;
        setPublishTime(publishTime);
        
        if(getHub().getOracleMode() == 1){
            getHub().setMockPythFeed(asset.pythId, price, conf, expo, emaPrice, emaConf, publishTime);
        }
        else if(getHub().getOracleMode() == 2){
            getHub().setOraclePrice(asset.pythId, Price({price: price, conf: conf, expo: expo, publishTime: publishTime}));
        }
    }

}
