// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import "../../interfaces/IWormhole.sol";
import "../../interfaces/ITokenBridge.sol";
import "../lendingHub/HubStructs.sol";
import "./SpokeState.sol";

contract SpokeGetters is SpokeState, Context, HubStructs {
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

    /**
    * Check if an address has been registered on the Hub yet (through the registerAsset function)
    * Errors out if assetAddress has not been registered yet
    * @param assetAddress - The address to be checked
    */
    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(registered_info.exists, "Unregistered asset");
    }
}