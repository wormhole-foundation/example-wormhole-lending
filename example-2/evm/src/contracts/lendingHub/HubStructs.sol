// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract HubStructs {
    struct VaultAmount {
        uint256 deposited;
        uint256 borrowed;
    }

    struct AccrualIndices {
        uint256 deposted;
        uint256 borrowed;
        uint256 lastBlock;
    }

    struct AssetInfo {
        uint256 collateralizationRatio;
        uint256 reserveFactor;
    }
}