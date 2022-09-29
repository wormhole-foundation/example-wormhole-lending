pragma solidity ^0.8.0;

contract MockPyth {
    // Mapping of cached price information
    // priceId => PriceInfo
    mapping(bytes32 => PriceInfo) latestPriceInfo;

    // A price with a degree of uncertainty, represented as a price +- a confidence interval.
    //
    // The confidence interval roughly corresponds to the standard error of a normal distribution.
    // Both the price and confidence are stored in a fixed-point numeric representation,
    // `x * (10^expo)`, where `expo` is the exponent.
    //
    // Please refer to the documentation at https://docs.pyth.network/consumers/best-practices for how
    // to how this price safely.
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    // PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }

    struct PriceInfo {
        uint256 attestationTime;
        uint256 arrivalTime;
        uint256 arrivalBlock;
        PriceFeed priceFeed;
    }

    function setLatestPriceInfo(bytes32 priceId, PriceInfo memory info) internal {
        latestPriceInfo[priceId] = info;
    }

    function getLatestPriceInfo(bytes32 priceId) internal view returns (PriceInfo memory info){
        return latestPriceInfo[priceId];
    }

    function queryPriceFeed(bytes32 id) public view returns (PriceFeed memory priceFeed){
        // Look up the latest price info for the given ID
        PriceInfo memory info = getLatestPriceInfo(id);
        require(info.priceFeed.id != 0, "no price feed found for the given price id");

        return info.priceFeed;
    }
}