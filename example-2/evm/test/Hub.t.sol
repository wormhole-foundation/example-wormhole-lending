// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/libraries/external/BytesLib.sol";

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

// TODO: add wormhole interface and use fork-url w/ mainnet

contract HubTest is Test, HubStructs, HubMessages, HubGetters, HubUtilities {
    using BytesLib for bytes;

    IERC20[] tokens;
    //string[] tokenNames = ["BNB", "ETH", "USDC", "SOL", "AVAX"];
    address[] tokenAddresses = [0x442F7f22b1EE2c842bEAFf52880d4573E9201158];
    uint256[] collateralizationRatios;
    Hub hub;

    IWormhole wormholeContract;
    ITokenBridge tokenBridgeContract;
    uint256 guardianSigner;
    WormholeSimulator public wormholeSimulator;

    bytes32 foreignTokenBridgeAddress;
    uint16 foreignChainId;

    function setUp() public {
        // initialize tokens with above tokens
        for (uint8 i = 0; i < tokenAddresses.length; i++) {
            tokens.push(IERC20(tokenAddresses[i]));
            collateralizationRatios.push(110000000000000000000); // all tokens have min collat ratio of 110%
        }

        // this will be used to sign wormhole messages
        guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        // set up Wormhole using Wormhole existing
        wormholeSimulator = new WormholeSimulator(vm.envAddress("TESTING_WORMHOLE_ADDRESS"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        wormholeContract = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormholeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID")), "wrong chainId");
        require(wormholeContract.messageFee() == vm.envUint("TESTING_WORMHOLE_MESSAGE_FEE"), "wrong messageFee");
        require(
            wormholeContract.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_WORMHOLE_GUARDIAN_SET_INDEX")),
            "wrong guardian set index"
        );

        // set up Token Bridge
        tokenBridgeContract = ITokenBridge(vm.envAddress("TESTING_TOKEN_BRIDGE_ADDRESS"));

        // verify Token Bridge state from fork
        require(tokenBridgeContract.chainId() == uint16(vm.envUint("TESTING_WORMHOLE_CHAINID")), "wrong chainId");

        // foreign token bridge (ethereum)
        foreignTokenBridgeAddress = vm.envBytes32("TESTING_FOREIGN_TOKEN_BRIDGE_ADDRESS");
        foreignChainId = uint16(vm.envUint("TESTING_FOREIGN_CHAIN_ID"));

        // initialize Hub contract
        uint8 wormholeFinality = 1;
        hub = new Hub(address(wormholeContract), address(tokenBridgeContract), msg.sender, wormholeFinality);
    }

    function testEncodeDepositPayload() public {
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))))
        });
        address assetAddress = address(tokens[0]);
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
        address assetAddress = address(tokens[0]);
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
        address assetAddress = address(tokens[0]);
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
        address assetAddress = address(tokens[0]);
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

    function encodePayload3Message(
        ITokenBridge.TransferWithPayload memory transfer,
        // wormhole related
        IWormhole.WormholeBodyParams memory wormholeParams
    ) public returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            wormholeParams.timestamp,
            wormholeParams.nonce,
            wormholeParams.emitterChainId,
            wormholeParams.emitterAddress,
            wormholeParams.sequence,
            wormholeParams.consistencyLevel,
            abi.encodePacked(
                transfer.payloadID,
                transfer.amount,
                transfer.tokenAddress,
                transfer.tokenChain,
                transfer.to,
                transfer.toChain,
                transfer.fromAddress,
                transfer.payload
            )
        );
    }

    function encodeVM(
        uint8 version,
        uint32 timestamp,
        uint32 nonce,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        uint8 consistencyLevel,
        bytes calldata payload
    ) public returns (bytes memory encodedVm) {
        encodedVm = abi.encodePacked(
            version, timestamp, nonce, emitterChainId, emitterAddress, sequence, consistencyLevel, payload
        );
    }

    // test register
    function testRegister() public {
        address assetAddress = address(tokens[0]);

        // register asset
        hub.registerAsset(assetAddress, collateralizationRatios[0], 0, bytes32(0), 18);

        // TODO: get rid of this getAssetAddressInfo function from Hub.sol, expose the function in Getters
        AssetInfo memory info = hub.getAssetAddressInfo(assetAddress);

        require(
            (info.collateralizationRatio == collateralizationRatios[0]) && (info.decimals == 18) && (info.exists),
            "didn't register properly"
        );
    }

    function getWrappedInfo(address assetAddress) internal returns (ITokenImplementation wrapped) {
        // 
        wrapped = ITokenImplementation(assetAddress);
        console.log("wrapped chain id", wrapped.chainId());
        console.log("wrapped native contract");
        console.logBytes32(wrapped.nativeContract());
    }

    function getSignedWHMsg(ITokenBridge.TransferWithPayload memory transfer) internal returns (bytes memory encodedVM) {
        //  construct WH message
        bytes memory message = encodePayload3Message(
            transfer,
            IWormhole.WormholeBodyParams({
                timestamp: 0,
                nonce: 0,
                emitterChainId: foreignChainId,
                emitterAddress: foreignTokenBridgeAddress,
                sequence: 1,
                consistencyLevel: 15
            })
        );
        
        // get hash for signature
        bytes32 messageHash = keccak256(abi.encodePacked(keccak256(message)));

        // Sign the hash with the devnet guardian private key
        IWormhole.Signature[] memory sigs = new IWormhole.Signature[](1);
        (sigs[0].v, sigs[0].r, sigs[0].s) = vm.sign(guardianSigner, messageHash);
        sigs[0].guardianIndex = 0;

        encodedVM = abi.encodePacked(
            uint8(1), // version
            wormholeContract.getCurrentGuardianSetIndex(),
            uint8(sigs.length),
            sigs[0].guardianIndex,
            sigs[0].r,
            sigs[0].s,
            sigs[0].v - 27,
            message
        );
    }

    function doRegister(address assetAddress, uint256 collateralizationRatio, uint256 reserveFactor, bytes32 pythId, uint8 decimals) internal {
        // register asset
        hub.registerAsset(assetAddress, collateralizationRatio, reserveFactor, pythId, decimals);
    }

    // create Deposit payload and package it into TokenBridgePayload into WH message and send the deposit
    function doDeposit(address vault, address assetAddress, uint256 assetAmount) internal returns (bytes memory encodedVM) {
        // create Deposit payload
        PayloadHeader memory header = PayloadHeader({
            payloadID: uint8(1),
            sender: vault //address(uint160(uint(keccak256(abi.encodePacked(block.timestamp)))))
        });
        DepositPayload memory myPayload = DepositPayload({header: header, assetAddress: assetAddress, assetAmount: assetAmount});
        bytes memory serialized = encodeDepositPayload(myPayload);

        // get wrapped info
        ITokenImplementation wrapped = getWrappedInfo(assetAddress);
        
        // TokenBridgePayload
        ITokenBridge.TransferWithPayload memory transfer = ITokenBridge.TransferWithPayload({
            payloadID: 3,
            amount: assetAmount,
            tokenAddress: wrapped.nativeContract(),
            tokenChain: wrapped.chainId(),
            to: bytes32(uint256(uint160(address(hub)))),
            toChain: wormholeContract.chainId(),
            fromAddress: bytes32(uint256(uint160(msg.sender))),
            payload: serialized
        });

        encodedVM = getSignedWHMsg(transfer);

        // complete deposit
        hub.completeDeposit(encodedVM);
    }

    // test deposit
    function testDeposit() public {        
        address vault = msg.sender;
        address assetAddress = address(tokenAddresses[0]);
        uint256 assetAmount = 502;
        uint256 collateralizationRatio = collateralizationRatios[0];
        uint8 decimals = 18;
        uint256 reserveFactor = 0;
        bytes32 pythId = bytes32(0);

        // call register
        doRegister(assetAddress, collateralizationRatio, reserveFactor, pythId, decimals);

        // TODO: get rid of this getAssetAddressInfo function from Hub.sol, expose the function in Getters
        AssetInfo memory info = hub.getAssetAddressInfo(assetAddress);
        AssetInfo memory info2 = getAssetInfo(assetAddress);



        uint256 deposited0;
        uint256 borrowed0;
        uint256 deposited1;
        uint256 borrowed1;

        VaultAmount memory global0;
        VaultAmount memory global1;

        VaultAmount memory vault0;
        VaultAmount memory vault1;

        (deposited0, borrowed0) = hub.getAmountsGlobal(assetAddress);
        vault0 = getVaultAmounts(msg.sender, assetAddress);


        // call deposit
        doDeposit(vault, assetAddress, assetAmount);
        


        (deposited1, borrowed1) = hub.getAmountsGlobal(assetAddress);
        // TODO: why does specifying msg.sender fix all?? Seems it assumes incorrect msg.sender by default
        vault1 = hub.getAmountsVault(msg.sender, assetAddress);

        console.log("Deposited before globally: ", deposited0);
        console.log("Deposited after globally: ", deposited1);

        console.log("Borrowed before globally: ", borrowed0);
        console.log("Borrowed after globally: ", borrowed1);

        console.log("Vault before: ", vault0.deposited, vault0.borrowed);
        console.log("Vault after: ", vault1.deposited, vault1.borrowed);
    }
}
