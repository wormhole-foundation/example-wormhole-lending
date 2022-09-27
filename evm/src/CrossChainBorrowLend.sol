// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
        address evmTargetContractAddress_,
        address collateralAsset_,
        uint256 collateralizationRatio_,
        address borrowingAsset_
    ) {
        state.owner = msg.sender;
        state.wormholeContractAddress = wormholeContractAddress_;
        state.consistencyLevel = consistencyLevel_;

        state.priceOracleAddress = priceOracleAddress_;

        state.targetChainId = targetChainId_;
        state.evmTargetContractAddress = evmTargetContractAddress_;

        state.collateralAssetAddress = collateralAsset_;
        state.collateralizationRatio = collateralizationRatio_;

        state.borrowingAssetAddress = borrowingAsset_;
    }

    function depositCollateral(uint256 amount) public {
        // TODO
    }

    struct RandomStruct {
        uint256 bleh;
    }

    function getOraclePrices() internal returns (uint256, uint256) {
        // TODO
        return (0, 0);
    }

    function initiateBorrowOnTargetChain(uint256 amount) public {
        // For EVMs, same private key will be used for borrowing-lending activity.
        // When introducing other chains (e.g. Cosmos), need to do wallet registration
        // so we can access a map of a non-EVM address based on this EVM borrower
        AssetAmounts memory amounts = state.accountAssets[msg.sender];

        // Need to calculate how much someone can borrow
        (
            uint256 collateralAssetPrice,
            uint256 borrowAssetPrice
        ) = getOraclePrices();

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

    function borrow(bytes calldata encodedVm) public {}

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
}
