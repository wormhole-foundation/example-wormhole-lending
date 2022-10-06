// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./SpokeSetters.sol";
import "./SpokeStructs.sol";
import "./SpokeMessages.sol";
import "./SpokeGetters.sol";

contract Spoke is SpokeSetters, SpokeGetters, SpokeStructs, SpokeMessages {
    constructor(uint16 chainId_, address wormhole_, address tokenBridge_) {
        setOwner(_msgSender());
        setChainId(chainId_);
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
    }

    function depositCollateral() public returns (uint64) {}

    function withdrawCollateral() public returns (uint64) {}

    function borrow() public returns (uint64) {}

    function repay() public returns (uint64) {}

    function liquidate(
        address vault,
        LiquidationRepay[] memory repay,
        LiquidationReceipt[] memory receipt
    ) public returns (uint64) {}

    function sendWormholeMessage(bytes memory payload)
        internal
        returns (uint64 sequence)
    {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }
}