// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";

contract HubInterestUtilities is HubSpokeStructs, HubGetters, HubSetters {
    
    /**
     * Assets accrue interest over time, so at any given point in time the value of an asset is (amount of asset on day 1) * (the amount of interest that has accrued).
     *
     * @param {uint256} denormalizedAmount - The true amount of an asset
     * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
     * So, (interestAccrualIndex/interestAccrualIndexPrecision) represents the interest accrued (this is initialized to 1 at the start of the protocol)
     * @return {uint256} The normalized amount of the asset
     */

    function normalizeAmount(uint256 denormalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (denormalizedAmount * getInterestAccrualIndexPrecision()) / interestAccrualIndex;
    }

    /**
     * Similar to 'normalizeAmount', takes a normalized value (amount of an asset) and denormalizes it.
     *
     * @param {uint256} normalizedAmount - The normalized amount of an asset
     * @param {uint256} interestAccrualIndex - The amount of interest that has accrued, multiplied by getInterestAccrualIndexPrecision().
     * @return {uint256} The true amount of the asset
     */
    function denormalizeAmount(uint256 normalizedAmount, uint256 interestAccrualIndex) public view returns (uint256) {
        return (normalizedAmount * interestAccrualIndex) / getInterestAccrualIndexPrecision();
    }

    /**
     * Denormalize both the 'deposited' and 'borrowed' values in the 'VaultAmount' struct, using the interest accrual indices corresponding
     * to deposit and borrow for the asset at address 'assetAddress'.
     * @param {VaultAmount} va - The amount deposited and borrowed for an asset in a vault. Stored as two uint256s.
     * @param {address} assetAddress - The address of the asset that 'va' is showing the amounts of.
     * @return {uint256} The denormalized amounts of 'assetAddress' that have been deposited and borrowed in the 'va' vault
     */
    function denormalizeVaultAmount(VaultAmount memory va, address assetAddress)
        internal
        view
        returns (VaultAmount memory)
    {
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);
        uint256 denormalizedDeposited = denormalizeAmount(va.deposited, indices.deposited);
        uint256 denormalizedBorrowed = denormalizeAmount(va.borrowed, indices.borrowed);
        return VaultAmount({deposited: denormalizedDeposited, borrowed: denormalizedBorrowed});
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

        accrualIndices.deposited += (interestFactor * (reservePrecision - reserveFactor) * borrowed) / reservePrecision / deposited;

        setInterestAccrualIndices(assetAddress, accrualIndices);
    }
}
