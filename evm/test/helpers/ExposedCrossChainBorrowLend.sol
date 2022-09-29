// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {NormalizedAmounts} from "../../src/CrossChainBorrowLendStructs.sol";
import {CrossChainBorrowLend} from "../../src/CrossChainBorrowLend.sol";
import "forge-std/Test.sol";

import "forge-std/console.sol";

contract ExposedCrossChainBorrowLend is CrossChainBorrowLend {
    constructor(
        address wormholeContractAddress_,
        uint8 consistencyLevel_,
        address mockPythAddress_,
        uint16 targetChainId_,
        bytes32 targetContractAddress_,
        address collateralAsset_,
        bytes32 collateralAssetPythId_,
        uint256 collateralizationRatio_,
        address borrowingAsset_,
        bytes32 borrowingAssetPythId_,
        uint256 repayGracePeriod_
    )
        CrossChainBorrowLend(
            wormholeContractAddress_,
            consistencyLevel_,
            mockPythAddress_,
            targetChainId_,
            targetContractAddress_,
            collateralAsset_,
            collateralAssetPythId_,
            collateralizationRatio_,
            borrowingAsset_,
            borrowingAssetPythId_,
            repayGracePeriod_
        )
    {
        // nothing else
    }

    function EXPOSED_computeInterestProportion(
        uint256 secondsElapsed,
        uint256 intercept,
        uint256 coefficient
    ) external view returns (uint256) {
        return
            computeInterestProportion(secondsElapsed, intercept, coefficient);
    }

    function EXPOSED_updateInterestAccrualIndex() external {
        return updateInterestAccrualIndex();
    }

    function EXPOSED_maxAllowedToBorrowWithPrices(
        address account,
        uint64 collateralPrice,
        uint64 borrowAssetPrice
    ) external view returns (uint256) {
        return
            maxAllowedToBorrowWithPrices(
                account,
                collateralPrice,
                borrowAssetPrice
            );
    }

    function EXPOSED_maxAllowedToWithdrawWithPrices(
        address account,
        uint64 collateralPrice,
        uint64 borrowAssetPrice
    ) external view returns (uint256) {
        return
            maxAllowedToWithdrawWithPrices(
                account,
                collateralPrice,
                borrowAssetPrice
            );
    }

    function EXPOSED_accountAssets(address account)
        external
        view
        returns (NormalizedAmounts memory)
    {
        return state.accountAssets[account];
    }

    function HACKED_setTotalAssetsDeposited(uint256 amount) external {
        state.totalAssets.deposited = amount;
    }

    function HACKED_setTotalAssetsBorrowed(uint256 amount) external {
        state.totalAssets.borrowed = amount;
    }

    function HACKED_setLastActivityBlockTimestamp(uint256 timestamp) external {
        state.lastActivityBlockTimestamp = timestamp;
    }

    function HACKED_setAccountAssetsDeposited(address account, uint256 amount)
        external
    {
        state.accountAssets[account].sourceDeposited = amount;
    }

    function HACKED_setAccountAssetsBorrowed(address account, uint256 amount)
        external
    {
        state.accountAssets[account].targetBorrowed = amount;
    }
}
