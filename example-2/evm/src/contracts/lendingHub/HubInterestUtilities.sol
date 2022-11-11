// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";

contract HubInterestUtilities is HubSpokeStructs, HubGetters, HubSetters {
    /**
     *
     *  The following two functions describe the Interest Rate Model of the whole protocol!
     *  TODO: IMPORTANT! Substitute this function out for whatever desired interest rate model you wish to have
     *
     */

    /*
     * Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued).
     * This function updates both the deposit and borrow interest accrual indices of the asset. 
     * @param {address} assetAddress - The asset to update the interest accrual indices of
     */
    function updateAccrualIndices(address assetAddress) internal {
        uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
        uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;
        uint256 deposited = getTotalAssetsDeposited(assetAddress);
        AccrualIndices memory accrualIndices = getInterestAccrualIndices(assetAddress);
        if (secondsElapsed == 0) {
            // no need to update anything
            return;
        }
        accrualIndices.lastBlock = block.timestamp;
        if (deposited == 0) {
            // avoid divide by 0 due to 0 deposits
            return;
        }
        uint256 borrowed = getTotalAssetsBorrowed(assetAddress);
        setLastActivityBlockTimestamp(assetAddress, block.timestamp);
        InterestRateModel memory interestRateModel = getInterestRateModel(assetAddress);
        uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);
        uint256 reserveFactor = assetInfo.interestRateModel.reserveFactor;
        uint256 reservePrecision = assetInfo.interestRateModel.reservePrecision;
        accrualIndices.borrowed += interestFactor;

        accrualIndices.deposited +=
            (interestFactor * (reservePrecision - reserveFactor) * borrowed) / reservePrecision / deposited;

        setInterestAccrualIndices(assetAddress, accrualIndices);
    }

    function computeSourceInterestFactor(
        uint256 secondsElapsed,
        uint256 deposited,
        uint256 borrowed,
        InterestRateModel memory interestRateModel
    ) internal pure returns (uint256) {
        if (deposited == 0) {
            return 0;
        }

        return (
            secondsElapsed
                * (interestRateModel.rateIntercept + (interestRateModel.rateCoefficientA * borrowed) / deposited)
                / interestRateModel.ratePrecision
        ) / 365 / 24 / 60 / 60;
    }

    /**
     *
     *  End Interest Rate Model
     *
     */

    /**
     * Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued).
     *
     * @param {uint256} denormalizedAmount - The true amount of an asset
     * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
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
     * Similar to 'normalizeAmount', takes a normalized value (amount of an asset) and denormalizes it.
     *
     * @param {uint256} normalizedAmount - The normalized amount of an asset
     * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
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
     * Divide helper function, for rounding
     * @param dividend - the dividend
     * @param divisor - the divisor
     * @param round - Whether or not to round up (Round.UP) or round down (Round.DOWN)
     * @return dividend/divisor, rounded appropriately
     */
    function divide(uint256 dividend, uint256 divisor, Round round) internal view returns (uint256) {
        uint256 modulo = dividend % divisor;
        uint256 quotient = dividend / divisor;
        if (modulo == 0 || round == Round.DOWN) {
            return quotient;
        }
        return quotient + 1;
    }
}
