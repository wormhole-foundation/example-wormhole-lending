// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";

contract Hub is HubSetters, HubGetters, HubStructs, HubMessages, HubEvents {
    constructor(uint16 chainId_, address wormhole_, address tokenBridge_) {
        setOwner(_msgSender());
        setChainId(chainId_);
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
    }

    function depositCollateral(address token, uint256 amount) public {
        emit EventDepositCollateral(msg.sender, token, amount);
    }

    function withdrawCollateral() public {}

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