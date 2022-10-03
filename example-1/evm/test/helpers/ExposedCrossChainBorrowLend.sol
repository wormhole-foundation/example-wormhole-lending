// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "../../src/CrossChainBorrowLendStructs.sol";
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

    function EXPOSED_computeSourceInterestFactor(
        uint256 secondsElapsed,
        uint256 intercept,
        uint256 coefficient
    ) external view returns (uint256) {
        return
            computeSourceInterestFactor(secondsElapsed, intercept, coefficient);
    }

    function EXPOSED_computeTargetInterestFactor(
        uint256 secondsElapsed,
        uint256 intercept,
        uint256 coefficient
    ) external view returns (uint256) {
        return
            computeTargetInterestFactor(secondsElapsed, intercept, coefficient);
    }

    function EXPOSED_updateSourceInterestAccrualIndex() external {
        return updateSourceInterestAccrualIndex();
    }

    function EXPOSED_updateTargetInterestAccrualIndex() external {
        return updateTargetInterestAccrualIndex();
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
        returns (SourceTargetUints memory)
    {
        return state.accountAssets[account];
    }

    function HACKED_setAccountAssets(
        address account,
        uint256 sourceDeposited,
        uint256 sourceBorrowed,
        uint256 targetDeposited,
        uint256 targetBorrowed
    ) public {
        // account
        state.accountAssets[account].source.deposited = sourceDeposited;
        state.accountAssets[account].source.borrowed = sourceBorrowed;
        state.accountAssets[account].target.deposited = targetDeposited;
        state.accountAssets[account].target.borrowed = targetBorrowed;
        // total
        state.totalAssets.source.deposited = sourceDeposited;
        state.totalAssets.source.borrowed = sourceBorrowed;
        state.totalAssets.target.deposited = targetDeposited;
        state.totalAssets.target.borrowed = targetBorrowed;
    }

    function HACKED_resetAccountAssets(address account) public {
        HACKED_setAccountAssets(account, 0, 0, 0, 0);
    }

    function HACKED_setLastActivityBlockTimestamp(uint256 timestamp) public {
        state.lastActivityBlockTimestamp = timestamp;
    }
}
