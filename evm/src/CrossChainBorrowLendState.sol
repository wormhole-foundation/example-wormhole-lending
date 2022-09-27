// SPDX-License-Identifier: UNLICENSED

import {AssetAmounts} from "./CrossChainBorrowLendStructs.sol";

contract CrossChainBorrowLendStorage {
    struct State {
        uint96 constant PRECISION = 1e8;
        address owner;
        // wormhole things
        address wormholeContractAddress;
        uint8 consistencyLevel;
        uint16 targetChainId;
        // price oracle
        address priceOracleAddress;
        address evmTargetContractAddress;
        // borrow and lend activity
        address collateralAssetAddress;
        uint256 collateralizationRatio;
        address borrowingAssetAddress;
        mapping(address => AssetAmounts) accountAssets;
    }
}

contract CrossChainBorrowLendState {
    CrossChainBorrowLendStorage.State state;
}
