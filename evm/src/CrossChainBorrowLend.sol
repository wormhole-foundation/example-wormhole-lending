// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IWormhole.sol";
import "./libraries/external/BytesLib.sol";

import "./CrossChainBorrowLendState.sol";
import "./CrossChainBorrowLendStructs.sol";

contract CrossChainBorrowLend is CrossChainBorrowLendState {
    using BytesLib for bytes;

    constructor(
        address wormholeContractAddress_,
        uint8 consistencyLevel_,
        address priceOracleAddress_,
        uint16 targetChainId_,
        bytes32 targetContractAddress_,
        address collateralAsset_,
        uint256 collateralizationRatio_,
        address borrowingAsset_
    ) {
        state.owner = msg.sender;
        state.wormholeContractAddress = wormholeContractAddress_;
        state.consistencyLevel = consistencyLevel_;

        state.priceOracleAddress = priceOracleAddress_;

        state.targetChainId = targetChainId_;
        state.targetContractAddress = targetContractAddress_;

        state.collateralAssetAddress = collateralAsset_;
        state.collateralizationRatio = collateralizationRatio_;
        state.collateralizationRatioPrecision = 1e8; // fixed

        state.borrowingAssetAddress = borrowingAsset_;
    }

    function collateralToken() internal view returns (IERC20) {
        return IERC20(state.collateralAssetAddress);
    }

    function collateralTokenDecimals() internal view returns (uint8) {
        return IERC20Metadata(state.collateralAssetAddress).decimals();
    }

    function borrowToken() internal view returns (IERC20) {
        return IERC20(state.borrowingAssetAddress);
    }

    function borrowTokenDecimals() internal view returns (uint8) {
        return IERC20Metadata(state.borrowingAssetAddress).decimals();
    }

    function depositCollateral(uint256 amount) public {
        require(amount > 0, "nothing to deposit");

        SafeERC20.safeTransferFrom(
            collateralToken(),
            msg.sender,
            address(this),
            amount
        );
    }

    struct RandomStruct {
        uint256 bleh;
    }

    function getOraclePrices() internal view returns (uint256, uint256) {
        // TODO
        return (0, 0);
    }

    function accrueInterest() internal {
        if (block.timestamp == state.lastBorrowBlockTimestamp) {
            // nothing to do
            return;
        }

        // Fixed borrow rate in this example. Use your own interest rate model here.
        uint256 annualInterestRate = 2e16; // 2%

        // uint256 accrued = (state.totalCollateralLiquidity *
        //     interestRate *
        //     (block.timestamp - state.lastBorrowBlockTimestamp)) /
        //     interestRatePrecision;
    }

    function initiateBorrowOnTargetChain(uint256 amount) public {
        require(amount > 0, "nothing to borrow");

        // For EVMs, same private key will be used for borrowing-lending activity.
        // When introducing other chains (e.g. Cosmos), need to do wallet registration
        // so we can access a map of a non-EVM address based on this EVM borrower
        AssetAmounts memory amounts = state.accountAssets[msg.sender];

        // Need to calculate how much someone can borrow
        (
            uint256 collateralAssetPriceInUSD,
            uint256 borrowAssetPriceInUSD
        ) = getOraclePrices();

        uint256 maxAllowedToBorrow = (amounts.depositedAmount *
            state.collateralizationRatio *
            collateralAssetPriceInUSD *
            10**borrowTokenDecimals()) /
            (state.collateralizationRatioPrecision *
                borrowAssetPriceInUSD *
                10**collateralTokenDecimals()) -
            amounts.borrowedAmount;
        require(amount < maxAllowedToBorrow, "amount >= maxAllowedToBorrow");

        // update borrowed amount
        state.accountAssets[msg.sender].borrowedAmount += amount;

        IWormhole(state.wormholeContractAddress).publishMessage(
            0, // nonce
            encodeBorrowWormholePayload(
                BorrowWormholePayload({
                    borrower: msg.sender,
                    collateralAddress: state.collateralAssetAddress,
                    collateralAmount: amounts.depositedAmount,
                    borrowAddress: state.borrowingAssetAddress,
                    borrowAmount: amounts.borrowedAmount
                })
            ),
            state.consistencyLevel
        );
    }

    function borrow(bytes calldata encodedVm) public {
        // add replay protection
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedVm);
        require(valid, reason);

        // verify emitter
        require(verifyEmitter(parsed), "invalid emitter");

        // completed
        state.completedBorrows[parsed.hash] = true;

        // decode
        BorrowWormholePayload memory params = decodeBorrowWormholePayload(
            parsed.payload
        );

        // correct assets?
        require(verifyAssetMeta(params), "invalid asset metadata");

        // TODO: check if we can release funds and transfer to borrower
        require(
            params.borrowAmount < state.totalCollateralLiquidity,
            "not enough liquidity"
        );

        SafeERC20.safeTransferFrom(
            collateralToken(),
            address(this),
            msg.sender,
            params.borrowAmount
        );
    }

    function verifyEmitter(IWormhole.VM memory parsed)
        internal
        view
        returns (bool)
    {
        return
            parsed.emitterAddress == state.targetContractAddress &&
            parsed.emitterChainId == state.targetChainId;
    }

    function verifyAssetMeta(BorrowWormholePayload memory params)
        internal
        view
        returns (bool)
    {
        return
            params.collateralAddress == state.borrowingAssetAddress &&
            params.borrowAddress == state.collateralAssetAddress;
    }

    function encodeBorrowWormholePayload(BorrowWormholePayload memory params)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                params.borrower,
                params.collateralAddress,
                params.collateralAmount,
                params.borrowAddress,
                params.borrowAmount
            );
    }

    function decodeBorrowWormholePayload(bytes memory serialized)
        internal
        pure
        returns (BorrowWormholePayload memory params)
    {
        uint256 index = 0;
        params.borrower = serialized.toAddress(index += 20);
        params.collateralAddress = serialized.toAddress(index += 20);
        params.collateralAmount = serialized.toUint256(index += 32);
        params.borrowAddress = serialized.toAddress(index += 20);
        params.borrowAmount = serialized.toUint256(index += 32);

        require(index == serialized.length, "index != serialized.length");
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(state.wormholeContractAddress);
    }
}
