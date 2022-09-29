// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

interface IMockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    struct PriceFeed {
        bytes32 id;
        Price price;
        Price emaPrice;
    }

    struct PriceInfo {
        uint256 attestationTime;
        uint256 arrivalTime;
        uint256 arrivalBlock;
        PriceFeed priceFeed;
    }

    function queryPriceFeed(bytes32 id) external view returns (PriceFeed memory priceFeed);
}