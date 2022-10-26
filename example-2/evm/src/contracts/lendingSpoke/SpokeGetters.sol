// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "./SpokeState.sol";
import "../lendingHub/HubStructs.sol";

contract SpokeGetters is Context, HubStructs, SpokeState {
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

    function tokenBridgeAddress() public view returns (address) {
        return _state.provider.tokenBridge;
    }

    function consistencyLevel() internal view returns (uint8) {
        return _state.consistencyLevel;
    }

    function hubChainId() internal view returns (uint16) {
        return _state.hubChainId;
    }

    function hubContractAddress() internal view returns (address) {
        return _state.hubContractAddress;
    }

    function messageHashConsumed(bytes32 vmHash) internal view returns (bool) {
        return _state.consumedMessages[vmHash];
    }

    function getAssetInfo(address assetAddress) public view returns (AssetInfo memory) {
        return _state.assetInfos[assetAddress];
    }

   
}