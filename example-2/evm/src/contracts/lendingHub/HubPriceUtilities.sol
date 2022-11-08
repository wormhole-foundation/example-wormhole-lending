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
    * Get the price, through Pyth, of the asset at address assetAddress
    * @param {address} assetAddress - The address of the relevant asset
    * @return {uint64, uint64} The price (in USD) of the asset, from Pyth; the confidence (in USD) of the asset's price
    */
    function getOraclePrices(address assetAddress) internal view returns (uint64, uint64) {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        uint8 oracleMode = getOracleMode();

        int64 priceValue;
        uint64 confValue;

        if (oracleMode == 0) {
            // using Pyth price
            PythStructs.Price memory oraclePrice = getPythPriceStruct(assetInfo.pythId);

            priceValue = oraclePrice.price;
            confValue = oraclePrice.conf;
        } else if (oracleMode == 1) {
            // using mock Pyth price
            PythStructs.Price memory oraclePrice = getMockPythPriceStruct(assetInfo.pythId);

            priceValue = oraclePrice.price;
            confValue = oraclePrice.conf;
        } else {
            // using fake oracle price
            Price memory oraclePrice = getOraclePrice(assetInfo.pythId);

            priceValue = oraclePrice.price;
            confValue = oraclePrice.conf;
        }

        require(priceValue >= 0, "no negative price assets allowed in XC borrow-lend");

        // Users of Pyth prices should read: https://docs.pyth.network/consumers/best-practices
        // before using the price feed. Blindly using the price alone is not recommended.
        return (uint64(priceValue), confValue);
        // return uint64(feed.price.price);
    }

    /**
     * Using the pyth prices, get the total price of the assets deposited into the vault, and
     * total price of the assets borrowed from the vault (multiplied by their respecetive collatorization ratios)
     * @param {address} vaultOwner - The address of the owner of the vault
     * @return {(uint256, uint256)} The total price of the assets deposited into and borrowed from the vault, respectively
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
                denormalizedDeposited = denormalizeAmount(normalizedAmounts.deposited, indices.deposited);
                denormalizedBorrowed = denormalizeAmount(normalizedAmounts.borrowed, indices.borrowed);
            }

            (uint64 priceCollateral, uint64 priceDebt) = getPriceCollateralAndPriceDebt(asset);
            uint256 collateralizationRatioPrecision = getCollateralizationRatioPrecision();
            uint8 maxDecimals = getMaxDecimals();
            effectiveNotionalDeposited += denormalizedDeposited * priceCollateral
                * 10 ** (maxDecimals - assetInfo.decimals) * collateralizationRatioPrecision
                / assetInfo.collateralizationRatioDeposit; 
            effectiveNotionalBorrowed += denormalizedBorrowed * priceDebt * 10 ** (maxDecimals - assetInfo.decimals)
                * assetInfo.collateralizationRatioBorrow / collateralizationRatioPrecision;
        }

        return (effectiveNotionalDeposited, effectiveNotionalBorrowed);
    }

    function getPriceCollateralAndPriceDebt(address assetAddress)
        internal
        view
        returns (uint64 priceCollateral, uint64 priceDebt)
    {
        (uint64 price, uint64 conf) = getOraclePrices(assetAddress);
        // use conservative (from protocol's perspective) prices for collateral (low) and debt (high)--see https://docs.pyth.network/consume-data/best-practices#confidence-intervals
        (uint64 nConf, uint64 nConfPrecision) = getNConf();
        priceCollateral = price - nConf * conf / nConfPrecision;
        priceDebt = price + nConf * conf / nConfPrecision;
    }

    function getPriceDebt(address assetAddress) internal view returns (uint64) {
        (, uint64 debt) = getPriceCollateralAndPriceDebt(assetAddress);
        return debt;
    }

    function getPriceCollateral(address assetAddress) internal view returns (uint64) {
        (uint64 collateral, ) = getPriceCollateralAndPriceDebt(assetAddress);
        return collateral;
    }

    function getPrice(address assetAddress) internal view returns (uint64) {
        (uint64 price, ) = getOraclePrices(assetAddress);
        return price;
    }
    
}
