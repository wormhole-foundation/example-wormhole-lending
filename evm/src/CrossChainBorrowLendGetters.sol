// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IMockPyth.sol";
import "./interfaces/IWormhole.sol";
import "./CrossChainBorrowLendState.sol";

contract CrossChainBorrowLendGetters is CrossChainBorrowLendState {
    function owner() public view returns (address) {
        return state.owner;
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(state.wormholeContractAddress);
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

    function getOraclePrices() internal view returns (uint64, uint64) {
        IMockPyth.PriceFeed memory collateralFeed = mockPyth().queryPriceFeed(
            state.collateralAssetPythId
        );
        IMockPyth.PriceFeed memory borrowFeed = mockPyth().queryPriceFeed(
            state.borrowingAssetPythId
        );

        // sanity check the price feeds
        require(
            collateralFeed.price.price > 0 && borrowFeed.price.price > 0,
            "negative prices detected"
        );

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return (
            uint64(collateralFeed.price.price),
            uint64(borrowFeed.price.price)
        );
    }

    function collateralPriceIndex() internal view returns (uint256) {
        return state.collateralPriceIndex;
    }

    function mockPyth() internal view returns (IMockPyth) {
        return IMockPyth(state.mockPythAddress);
    }

    function normalizedLiquidity() internal view returns (uint256) {
        return state.totalAssets.deposited - state.totalAssets.borrowed;
    }
}
