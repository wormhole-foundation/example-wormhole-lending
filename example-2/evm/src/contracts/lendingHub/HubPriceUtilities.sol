// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IMockPyth.sol";
import "../HubSpokeStructs.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";
import "./HubInterestUtilities.sol";

contract HubPriceUtilities is HubSpokeStructs, HubGetters, HubSetters, HubInterestUtilities {
    /**
     * @notice Get the price, through Pyth, of the asset at address assetAddress
     * @param assetAddress - The address of the relevant asset
     * @return {uint64, uint64} The price (in USD) of the asset, from Pyth; the confidence (in USD) of the asset's price
     */
    function getOraclePrices(address assetAddress) internal view returns (uint64, uint64) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint8 oracleMode = getOracleMode();

        int64 priceValue;
        uint64 priceStandardDeviationsValue;

        if (oracleMode == 0) {
            // using Pyth price
            PythStructs.Price memory oraclePrice = getPythPriceStruct(assetInfo.pythId);

            priceValue = oraclePrice.price;
            priceStandardDeviationsValue = oraclePrice.conf;
        } else if (oracleMode == 1) {
            // using mock Pyth price
            PythStructs.Price memory oraclePrice = getMockPythPriceStruct(assetInfo.pythId);

            priceValue = oraclePrice.price;
            priceStandardDeviationsValue = oraclePrice.conf;
        } else {
            // using fake oracle price
            Price memory oraclePrice = getOraclePrice(assetInfo.pythId);

            priceValue = oraclePrice.price;
            priceStandardDeviationsValue = oraclePrice.conf;
        }

        require(priceValue >= 0, "no negative price assets allowed in XC borrow-lend");

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return (uint64(priceValue), priceStandardDeviationsValue);
        // return uint64(feed.price.price);
    }

    /**
     * @notice Using the pyth prices, get the total price of the assets deposited into the vault, and
     * total price of the assets borrowed from the vault (multiplied by their respecetive collateralization ratios)
     * The result will be multiplied by interestAccrualIndexPrecision * collateralizationRatioPrecision * pricePrecision * 10^(maxDecimals)
     * because we are denormalizing without dividing by this value, and we are multiplying by collateralizationRatios without dividing
     * by the precision, and we are using getPriceCollateralAndPriceDebt with returns the prices multiplied by pricePrecision
     * and we are multiplying by 10^maxDecimals to keep integers when we divide by 10^(decimals of each asset).
     * 
     * @param vaultOwner - The address of the owner of the vault
     * @return {(uint256, uint256)} The total price of the assets deposited into and borrowed from the vault, respectively,
     * multiplied by interestAccrualIndexPrecision * collateralizationRatioPrecision * pricePrecision
     */
    function getVaultEffectiveNotionals(address vaultOwner) internal view returns (uint256, uint256) {
        uint256 effectiveNotionalDeposited = 0;
        uint256 effectiveNotionalBorrowed = 0;

        address[] memory allowList = getAllowList();
        for (uint256 i = 0; i < allowList.length; i++) {
            address asset = allowList[i];

            AssetInfo memory assetInfo = getAssetInfo(asset);

            AccrualIndices memory indices = getInterestAccrualIndices(asset);

            uint256 denormalizedDeposited;
            uint256 denormalizedBorrowed;
            {
                VaultAmount memory normalizedAmounts = getVaultAmounts(vaultOwner, asset);
                denormalizedDeposited = normalizedAmounts.deposited * indices.deposited;
                denormalizedBorrowed = normalizedAmounts.borrowed * indices.borrowed;
            }

            (uint64 priceCollateral, uint64 priceDebt) = getPriceCollateralAndPriceDebt(asset);
            uint8 maxDecimals = getMaxDecimals();
            effectiveNotionalDeposited += denormalizedDeposited * priceCollateral
                * 10 ** (maxDecimals - assetInfo.decimals) * assetInfo.collateralizationRatioDeposit;
            effectiveNotionalBorrowed += denormalizedBorrowed * priceDebt * 10 ** (maxDecimals - assetInfo.decimals)
                * assetInfo.collateralizationRatioBorrow;
        }

        return (effectiveNotionalDeposited, effectiveNotionalBorrowed);
    }

    /**
     * @notice Gets priceCollateral and priceDebt, which are price - c*stdev and price + c*stdev, respectively
     * where c is a constant specified by the protocol (priceStandardDeviations),
     * and stdev is the standard deviation of the price.
     * Multiplies each of these values by getPricePrecision().
     * These values are used as lower and upper bounds of the price when determining whether to allow
     * borrows and withdraws
     *
     * @param assetAddress the address of the relevant asset
     * @return priceCollateral - getPricePrecision() * (price - c*stdev)
     * @return priceDebt - getPricePrecision() * (price + c*stdev)
     */
    function getPriceCollateralAndPriceDebt(address assetAddress)
        internal
        view
        returns (uint64 priceCollateral, uint64 priceDebt)
    {
        (uint64 price, uint64 conf) = getOraclePrices(assetAddress);
        // use conservative (from protocol's perspective) prices for collateral (low) and debt (high)--see https://docs.pyth.network/consume-data/best-practices#confidence-intervals
        uint64 priceStandardDeviations = getPriceStandardDeviations();
        uint64 pricePrecision = getPricePrecision();
        priceCollateral = 0;
        if (price * pricePrecision >= conf * priceStandardDeviations) {
            priceCollateral = price * pricePrecision - conf * priceStandardDeviations;
        }
        priceDebt = price * pricePrecision + conf * priceStandardDeviations;
    }

    /**
     * @notice Gets the value of priceDebt described above
     *
     * @param assetAddress the address of the relevant asset
     * @return priceDebt: getPricePrecision() * (price + c*stdev)
     */
    function getPriceDebt(address assetAddress) internal view returns (uint64) {
        (, uint64 debt) = getPriceCollateralAndPriceDebt(assetAddress);
        return debt;
    }

    /**
     * @notice Gets the value of priceCollateral described above
     *
     * @param assetAddress the address of the relevant asset
     * @return priceCollateral: getPricePrecision() * (price - c*stdev)
     */
    function getPriceCollateral(address assetAddress) internal view returns (uint64) {
        (uint64 collateral,) = getPriceCollateralAndPriceDebt(assetAddress);
        return collateral;
    }

    /**
     * @notice Gets the price of the asset (i.e. the mean of the confidence interval returned by Pyth)
     *
     * @param assetAddress the address of the relevant asset
     * @return price: getPricePrecision() * (price)
     */
    function getPrice(address assetAddress) internal view returns (uint64) {
        (uint64 price,) = getOraclePrices(assetAddress);
        return price * getPricePrecision();
    }
}
