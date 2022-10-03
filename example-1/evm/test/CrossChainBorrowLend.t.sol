// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/CrossChainBorrowLendStructs.sol";
import {ExposedCrossChainBorrowLend} from "./helpers/ExposedCrossChainBorrowLend.sol";
import {MyERC20} from "./helpers/MyERC20.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

// TODO: add wormhole interface and use fork-url w/ mainnet

contract CrossChainBorrowLendTest is Test {
    MyERC20 collateralToken;
    MyERC20 borrowedAssetToken;
    ExposedCrossChainBorrowLend borrowLendContract;

    bytes32 collateralAssetPythId;
    bytes32 borrowingAssetPythId;
    uint256 collateralizationRatio;

    function setUp() public {
        address wormholeAddress = msg.sender;
        address mockPythAddress = msg.sender;
        bytes32 targetContractAddress = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

        collateralToken = new MyERC20("WBNB", "WBNB", 18);
        borrowedAssetToken = new MyERC20("USDC", "USDC", 6);

        // 80%
        collateralizationRatio = 0.8e18;

        // TODO
        borrowLendContract = new ExposedCrossChainBorrowLend(
            wormholeAddress,
            1, // consistencyLevel
            mockPythAddress,
            2, // targetChainId (ethereum)
            targetContractAddress,
            address(collateralToken), // collateralAsset
            collateralAssetPythId,
            collateralizationRatio,
            address(borrowedAssetToken),
            borrowingAssetPythId,
            5 * 60 // gracePeriod (5 minutes)
        );
    }

    function testSourceComputeInterestFactor() public {
        // start from zero
        vm.warp(0);
        uint256 timeStart = block.timestamp;

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);
        uint256 secondsElapsed = block.timestamp - timeStart;

        // accrue interest with intercept and coefficient
        uint256 intercept = 0.02e18; // 2% starting rate
        uint256 coefficient = 0.001e18; // increase 10 basis points per 1% borrowed

        // set state for test
        uint256 sourceDeposited = 1e18; // 1 WBNB (18 decimals)
        uint256 sourceBorrowed = 0.5e18; // 0.5 WBNB (18 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            sourceDeposited,
            sourceBorrowed,
            0, // targetDeposited
            0 // targetBorrowed
        );

        // expect using the correct value (0.0205e18)
        {
            require(
                borrowLendContract.EXPOSED_computeSourceInterestFactor(
                    secondsElapsed,
                    intercept,
                    coefficient
                ) == 0.0205e18,
                "computeSourceInterestFactor(...) != expected"
            );
            require(
                borrowLendContract.EXPOSED_computeTargetInterestFactor(
                    secondsElapsed,
                    intercept,
                    coefficient
                ) == 0,
                "computeTargetInterestFactor(...) != expected"
            );
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }

    function testTargetComputeInterestFactor() public {
        // start from zero
        vm.warp(0);
        uint256 timeStart = block.timestamp;

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);
        uint256 secondsElapsed = block.timestamp - timeStart;

        // accrue interest with intercept and coefficient
        uint256 intercept = 0.02e18; // 2% starting rate
        uint256 coefficient = 0.001e18; // increase 10 basis points per 1% borrowed

        // set state for test
        uint256 targetDeposited = 100e6; // 100 USDC (6 decimals)
        uint256 targetBorrowed = 50e6; // 50 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            0, // sourceDeposited
            0, // sourceBorrowed
            targetDeposited,
            targetBorrowed
        );

        // expect using the correct value (0.0205e18)
        {
            require(
                borrowLendContract.EXPOSED_computeSourceInterestFactor(
                    secondsElapsed,
                    intercept,
                    coefficient
                ) == 0,
                "computeSourceInterestFactor(...) != expected"
            );
            require(
                borrowLendContract.EXPOSED_computeTargetInterestFactor(
                    secondsElapsed,
                    intercept,
                    coefficient
                ) == 0.0205e18,
                "computeTargetInterestFactor(...) != expected"
            );
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }

    function testUpdateSourceInterestAccrualIndex() public {
        // start from zero
        vm.warp(0);
        borrowLendContract.HACKED_setLastActivityBlockTimestamp(
            block.timestamp
        );

        // set state for test
        uint256 sourceDeposited = 200e18; // 200 WBNB (18 decimals)
        uint256 sourceBorrowed = 20e18; // 20 WBNB (18 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            sourceDeposited,
            sourceBorrowed,
            0, // targetDeposited
            0 // targetBorrowed
        );

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);

        // trigger accrual
        borrowLendContract.EXPOSED_updateSourceInterestAccrualIndex();

        {
            // expect using the correct value (1.02e18)
            require(
                borrowLendContract.sourceBorrowedInterestAccrualIndex() ==
                    1.02e18,
                "sourceBorrowedInterestAccrualIndex() != expected (first iteration)"
            );
            // expect using the correct value (1.002e18)
            require(
                borrowLendContract.sourceCollateralInterestAccrualIndex() ==
                    1.002e18,
                "sourceBollateralInterestAccrualIndex() != expected (first iteration)"
            );
        }

        // warp to 2 years in the future
        vm.warp(2 * 365 * 24 * 60 * 60);

        // trigger accrual again
        borrowLendContract.EXPOSED_updateSourceInterestAccrualIndex();

        {
            // expect using the correct value (1.04e18)
            require(
                borrowLendContract.sourceBorrowedInterestAccrualIndex() ==
                    1.04e18,
                "sourceBorrowedInterestAccrualIndex() != expected (second iteration)"
            );
            // expect using the correct value (1.004e18)
            require(
                borrowLendContract.sourceCollateralInterestAccrualIndex() ==
                    1.004e18,
                "sourceCollateralInterestAccrualIndex() != expected (second iteration)"
            );
        }

        // check denormalized deposit and borrowed. should be equal
        {
            DepositedBorrowedUints memory amounts = borrowLendContract
                .normalizedAmounts()
                .source;
            uint256 accruedDepositedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.deposited,
                    borrowLendContract.sourceCollateralInterestAccrualIndex()
                ) - sourceDeposited;
            uint256 accruedBorrowedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.borrowed,
                    borrowLendContract.sourceBorrowedInterestAccrualIndex()
                ) - sourceBorrowed;
            require(
                accruedDepositedInterest == accruedBorrowedInterest,
                "accruedDepositedInterest != accruedBorrowedInterest"
            );
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }

    function testUpdateTargetInterestAccrualIndex() public {
        // start from zero
        vm.warp(0);
        borrowLendContract.HACKED_setLastActivityBlockTimestamp(
            block.timestamp
        );

        // set state for test
        uint256 targetDeposited = 200e6; // 200 USDC (6 decimals)
        uint256 targetBorrowed = 20e6; // 20 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            0, // sourceDeposited
            0, // sourceBorrowed
            targetDeposited,
            targetBorrowed
        );

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);

        // trigger accrual
        borrowLendContract.EXPOSED_updateTargetInterestAccrualIndex();

        {
            // expect using the correct value (1.02e18)
            require(
                borrowLendContract.targetBorrowedInterestAccrualIndex() ==
                    1.02e18,
                "targetBorrowedInterestAccrualIndex() != expected (first iteration)"
            );
            // expect using the correct value (1.002e18)
            require(
                borrowLendContract.targetCollateralInterestAccrualIndex() ==
                    1.002e18,
                "targetCollateralInterestAccrualIndex() != expected (first iteration)"
            );
        }

        // warp to 2 years in the future
        vm.warp(2 * 365 * 24 * 60 * 60);

        // trigger accrual again
        borrowLendContract.EXPOSED_updateTargetInterestAccrualIndex();

        {
            // expect using the correct value (1.04e18)
            require(
                borrowLendContract.targetBorrowedInterestAccrualIndex() ==
                    1.04e18,
                "targetBorrowedInterestAccrualIndex() != expected (second iteration)"
            );
            // expect using the correct value (1.004e18)
            require(
                borrowLendContract.targetCollateralInterestAccrualIndex() ==
                    1.004e18,
                "targetCollateralInterestAccrualIndex() != expected (second iteration)"
            );
        }

        // check denormalized deposit and borrowed. should be equal
        {
            DepositedBorrowedUints memory amounts = borrowLendContract
                .normalizedAmounts()
                .target;
            uint256 accruedDepositedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.deposited,
                    borrowLendContract.sourceCollateralInterestAccrualIndex()
                ) - targetDeposited;
            uint256 accruedBorrowedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.borrowed,
                    borrowLendContract.sourceBorrowedInterestAccrualIndex()
                ) - targetBorrowed;
            require(
                accruedDepositedInterest == accruedBorrowedInterest,
                "accruedDepositedInterest != accruedBorrowedInterest"
            );
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }

    function testMaxAllowedToWithdraw() public {
        uint64 collateralPrice = 400; // WBNB
        uint64 borrowAssetPrice = 1; // USDC

        uint256 sourceDeposited = 1e18; // 1 WBNB (18 decimals)
        uint256 targetBorrowed = 100e6; // 100 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            sourceDeposited,
            0, // sourceBorrowed
            0, // targetDeposited
            targetBorrowed
        );

        uint256 maxAllowed = borrowLendContract
            .EXPOSED_maxAllowedToWithdrawWithPrices(
                msg.sender,
                collateralPrice,
                borrowAssetPrice
            );

        // expect 0.6875e18 (0.6875 WBNB)
        {
            require(maxAllowed == 0.6875e18, "maxAllowed != expected");
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }

    function testMaxAllowedToBorrow() public {
        uint64 collateralPrice = 400; // WBNB
        uint64 borrowAssetPrice = 1; // USDC

        uint256 sourceDeposited = 1e18; // 1 WBNB (18 decimals)
        uint256 targetBorrowed = 100e6; // 100 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssets(
            msg.sender,
            sourceDeposited,
            0, // sourceBorrowed
            0, // targetDeposited
            targetBorrowed
        );

        uint256 maxAllowed = borrowLendContract
            .EXPOSED_maxAllowedToBorrowWithPrices(
                msg.sender,
                collateralPrice,
                borrowAssetPrice
            );

        // expect 220e6 (220 USDC)
        {
            require(maxAllowed == 220e6, "maxAllowed != expected");
        }

        // clear
        borrowLendContract.HACKED_resetAccountAssets(msg.sender);
    }
}
