// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";

import "./HubState.sol";

contract HubGetters is HubState, Context {
    function owner() public view returns (address) {
        return _state.owner;
    }

    function chainId() public view returns (uint16) {
        return _state.provider.chainId;
    }

    function wormhole() internal view returns (IWormhole) {
        return IWormhole(_state.provider.wormhole);
    }

    function tokenBridge() public view returns (ITokenBridge) {
        return ITokenBridge(payable(_state.provider.tokenBridge));
    }

    function consistencyLevel() internal view returns (uint8) {
        return _state.consistencyLevel;
    }

    function getSpokeContract(uint16 chainId) internal view returns (address) {
        return _state.spokeContracts[chainId];
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getWormholePayload(bytes calldata encodedMessage) internal view returns (bytes) {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        require(verifyEmitter(parsed), "invalid emitter");

        require(!messageHashConsumed(parsed.hash), "message already confused");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    } 
}