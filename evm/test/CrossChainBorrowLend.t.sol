// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NormalizedAmounts, NormalizedTotalAmounts} from "../src/CrossChainBorrowLendStructs.sol";
import {ExposedCrossChainBorrowLend} from "./helpers/ExposedCrossChainBorrowLend.sol";
import {MyERC20} from "./helpers/MyERC20.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

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

    function testComputeInterestProportion() public {
        // start from zero
        vm.warp(0);
        uint256 timeStart = block.timestamp;

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);
        uint256 secondsElapsed = block.timestamp - timeStart;

        // accrue interest with intercept and coefficient
        uint256 intercept = 0.02e18; // 2% starting rate
        uint256 coefficient = 0.001e18; // increase 10 basis points per 1% borrowed

        // fake supply some amount
        uint256 deposited = 100e6; // 100 USDC (6 decimals)
        borrowLendContract.HACKED_setTotalAssetsDeposited(deposited);

        uint256 borrowed = 50e6; // 50 USDC (6 decimals)
        borrowLendContract.HACKED_setTotalAssetsBorrowed(borrowed);

        // we expect the interest accrued equal to the intercept
        uint256 interestProportion = borrowLendContract
            .EXPOSED_computeInterestProportion(
                secondsElapsed,
                intercept,
                coefficient
            );

        // expect using the correct value (0.0205e18)
        {
            require(
                interestProportion == 0.0205e18,
                "interestProportion != expected"
            );
        }

        // expect using calculation
        {
            uint256 expected = intercept + (coefficient * borrowed) / deposited;
            require(
                interestProportion == expected,
                "interestProportion != expected (computed)"
            );
        }

        // clear
        borrowLendContract.HACKED_setTotalAssetsDeposited(0);
        borrowLendContract.HACKED_setTotalAssetsBorrowed(0);
    }

    function testUpdateInterestAccrualIndex() public {
        // start from zero
        vm.warp(0);
        borrowLendContract.HACKED_setLastActivityBlockTimestamp(
            block.timestamp
        );

        // warp to 1 year in the future
        vm.warp(365 * 24 * 60 * 60);

        // fake supply some amount
        uint256 deposited = 200e6; // 200 USDC (6 decimals)
        borrowLendContract.HACKED_setTotalAssetsDeposited(deposited);

        uint256 borrowed = 20e6; // 20 USDC (6 decimals)
        borrowLendContract.HACKED_setTotalAssetsBorrowed(borrowed);

        // update
        borrowLendContract.EXPOSED_updateInterestAccrualIndex();

        {
            // expect using the correct value (1.02e18)
            require(
                borrowLendContract.borrowedInterestAccrualIndex() == 1.02e18,
                "borrowedInterestAccrualIndex() != expected (first iteration)"
            );
            // expect using the correct value (1.002e18)
            require(
                borrowLendContract.collateralInterestAccrualIndex() == 1.002e18,
                "collateralInterestAccrualIndex() != expected (first iteration)"
            );
        }

        // warp to 2 years in the future
        vm.warp(2 * 365 * 24 * 60 * 60);

        // update again
        borrowLendContract.EXPOSED_updateInterestAccrualIndex();

        {
            // expect using the correct value (1.02 * 1.02e18 = 1.0404e18)
            require(
                borrowLendContract.borrowedInterestAccrualIndex() == 1.0404e18,
                "borrowedInterestAccrualIndex() != expected (second iteration)"
            );
            // expect using the correct value (1.002 * 1.002e18 = 1.004004e18)
            require(
                borrowLendContract.collateralInterestAccrualIndex() ==
                    1.00404e18,
                "collateralInterestAccrualIndex() != expected (second iteration)"
            );
        }

        // check denormalized deposit and borrowed. should be equal
        {
            NormalizedTotalAmounts memory amounts = borrowLendContract
                .normalizedAmounts();
            uint256 accruedDepositedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.deposited,
                    borrowLendContract.collateralInterestAccrualIndex()
                ) - deposited;
            uint256 accruedBorrowedInterest = borrowLendContract
                .denormalizeAmount(
                    amounts.borrowed,
                    borrowLendContract.borrowedInterestAccrualIndex()
                ) - borrowed;
            require(
                accruedDepositedInterest == accruedBorrowedInterest,
                "accruedDepositedInterest != accruedBorrowedInterest"
            );
        }

        // clear
        borrowLendContract.HACKED_setTotalAssetsDeposited(0);
        borrowLendContract.HACKED_setTotalAssetsBorrowed(0);
    }

    function testMaxAllowedToWithdraw() public {
        uint64 collateralPrice = 400; // WBNB
        uint64 borrowAssetPrice = 1; // USDC

        uint256 deposited = 1e18; // 1 WBNB (18 decimals)
        borrowLendContract.HACKED_setAccountAssetsDeposited(
            msg.sender,
            deposited
        );

        uint256 borrowed = 100e6; // 100 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssetsBorrowed(
            msg.sender,
            borrowed
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
        borrowLendContract.HACKED_setAccountAssetsDeposited(msg.sender, 0);
        borrowLendContract.HACKED_setAccountAssetsBorrowed(msg.sender, 0);
    }

    function testMaxAllowedToBorrow() public {
        uint64 collateralPrice = 400; // WBNB
        uint64 borrowAssetPrice = 1; // USDC

        uint256 deposited = 1e18; // 1 WBNB (18 decimals)
        borrowLendContract.HACKED_setAccountAssetsDeposited(
            msg.sender,
            deposited
        );

        uint256 borrowed = 100e6; // 100 USDC (6 decimals)
        borrowLendContract.HACKED_setAccountAssetsBorrowed(
            msg.sender,
            borrowed
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
        borrowLendContract.HACKED_setAccountAssetsDeposited(msg.sender, 0);
        borrowLendContract.HACKED_setAccountAssetsBorrowed(msg.sender, 0);
    }
}
