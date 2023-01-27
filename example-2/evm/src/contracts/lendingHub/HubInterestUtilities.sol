// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";
import "forge-std/console.sol";

contract HubInterestUtilities is HubSpokeStructs, HubGetters, HubSetters {
    /*
     *
     *  The following three functions describe the Interest Rate Model of the whole protocol!
     *  TODO: IMPORTANT! Substitute this function out for whatever desired interest rate model you wish to have
     *
     */

    /**
     * @notice Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued).
     * This function updates both the deposit and borrow interest accrual indices of the asset. 
     *
     * @param assetAddress - The asset to update the interest accrual indices of
     */
    function updateAccrualIndices(address assetAddress) internal {
        setInterestAccrualIndices(assetAddress, getCurrentAccrualIndices(assetAddress));
        setLastActivityBlockTimestamp(assetAddress, block.timestamp);
    }

    function getCurrentAccrualIndices(address assetAddress) internal view returns (AccrualIndices memory) {
        uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
        uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;
        uint256 deposited = getTotalAssetsDeposited(assetAddress);
        AccrualIndices memory accrualIndices = getInterestAccrualIndices(assetAddress);
        if ((secondsElapsed != 0) && (deposited != 0)) {
            uint256 borrowed = getTotalAssetsBorrowed(assetAddress);
            PiecewiseInterestRateModel memory interestRateModel = getInterestRateModel(assetAddress);
            uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);
            AssetInfo memory assetInfo = getAssetInfo(assetAddress);
            uint256 reserveFactor = assetInfo.interestRateModel.reserveFactor;
            uint256 reservePrecision = assetInfo.interestRateModel.reservePrecision;
            accrualIndices.borrowed += interestFactor;
            accrualIndices.deposited +=
                (interestFactor * (reservePrecision - reserveFactor) * borrowed) / reservePrecision / deposited;
        }
        return accrualIndices;
    }

    function computeSourceInterestFactor(
        uint256 secondsElapsed,
        uint256 deposited,
        uint256 borrowed,
        PiecewiseInterestRateModel memory interestRateModel
    ) internal view returns (uint256) {
        if (deposited == 0) {
            return 0;
        }

        uint256[] memory kinks = interestRateModel.kinks;
        uint256[] memory rates = interestRateModel.rates;

        uint i = 0;
        uint256 interestRate = 0;
        while (borrowed * interestRateModel.ratePrecision > deposited * kinks[i]) {
            interestRate = rates[i];
            i += 1;

            if (i == rates.length) {
                return rates[i-1];
            }
        }

        // if zero borrows and nonzero deposits, then set interest rate for period to the rate intercept i.e. first kink; ow linearly interpolate between kinks
        if (i==0) {
            interestRate = rates[0];
        }
        else {
            interestRate += (rates[i] - rates[i-1]) * ((borrowed  - kinks[i-1] * deposited) / deposited) / (kinks[i] - kinks[i-1]);
        }

        return (getInterestAccrualIndexPrecision() * secondsElapsed * interestRate / interestRateModel.ratePrecision) / 365 / 24 / 60 / 60;
    }

    /*
     *
     *  End Interest Rate Model
     *
     */

    /**
     * @notice Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued).
     *
     * @param denormalizedAmount - The true amount of an asset
     * @param interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
     * So, (interestAccrualIndex/interestAccrualIndexPrecision) represents the interest accrued (this is initialized to 1 at the start of the protocol)
     * @return {uint256} The normalized amount of the asset
     */

    function normalizeAmount(uint256 denormalizedAmount, uint256 interestAccrualIndex, Round round)
        public
        view
        returns (uint256)
    {
        return divide(denormalizedAmount * getInterestAccrualIndexPrecision(), interestAccrualIndex, round);
    }

    /**
     * @notice Similar to 'normalizeAmount', takes a normalized value (amount of an asset) and denormalizes it.
     *
     * @param normalizedAmount - The normalized amount of an asset
     * @param interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
     * @return {uint256} The true amount of the asset
     */
    function denormalizeAmount(uint256 normalizedAmount, uint256 interestAccrualIndex, Round round)
        public
        view
        returns (uint256)
    {
        return divide(normalizedAmount * interestAccrualIndex, getInterestAccrualIndexPrecision(), round);
    }

    /**
     * @notice Get a user's account balance in an asset
     *
     * @param vaultOwner - the address of the user
     * @param assetAddress - the address of the asset
     * @return a struct with 'deposited' field and 'borrowed' field for the amount deposited and borrowed of the asset
     * multiplied by 10^decimal for that asset. Values are denormalized.
     */
    function getUserBalance(address vaultOwner, address assetAddress) public view returns (VaultAmount memory) {
        VaultAmount memory normalized = getVaultAmounts(vaultOwner, assetAddress);
        AccrualIndices memory interestAccrualIndex = getCurrentAccrualIndices(assetAddress);
        return VaultAmount({
            deposited: denormalizeAmount(normalized.deposited, interestAccrualIndex.deposited, Round.DOWN),
            borrowed: denormalizeAmount(normalized.borrowed, interestAccrualIndex.borrowed, Round.UP)
        });
    }

    /**
     * @notice Get the protocol's global balance in an asset
     *
     * @param assetAddress - the address of the asset
     * @return a struct with 'deposited' field and 'borrowed' field for the amount deposited and borrowed of the asset
     * multiplied by 10^decimal for that asset. Values are denormalized.
     */
    function getGlobalBalance(address assetAddress) public view returns (VaultAmount memory) {
        VaultAmount memory normalized = getGlobalAmounts(assetAddress);
        AccrualIndices memory interestAccrualIndex = getCurrentAccrualIndices(assetAddress);
        return VaultAmount({
            deposited: denormalizeAmount(normalized.deposited, interestAccrualIndex.deposited, Round.DOWN),
            borrowed: denormalizeAmount(normalized.borrowed, interestAccrualIndex.borrowed, Round.UP)
        });
    }


    /**
     * @notice Divide helper function, for rounding
     *
     * @param dividend - the dividend
     * @param divisor - the divisor
     * @param round - Whether or not to round up (Round.UP) or round down (Round.DOWN)
     * @return dividend/divisor, rounded appropriately
     */
    function divide(uint256 dividend, uint256 divisor, Round round) internal pure returns (uint256) {
        uint256 modulo = dividend % divisor;
        uint256 quotient = dividend / divisor;
        if (modulo == 0 || round == Round.DOWN) {
            return quotient;
        }
        return quotient + 1;
    }
}
