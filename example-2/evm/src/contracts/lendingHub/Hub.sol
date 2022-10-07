// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";

contract Hub is HubSetters, HubGetters, HubStructs, HubMessages, HubEvents {
    constructor(address wormhole_, address tokenBridge_, address mockPythAddress_, uint8 consistencyLevel_) {
        setOwner(_msgSender());
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
        setPyth(mockPythAddress_);

        setConsistencyLevel(consistencyLevel_);

    }

    function registerSpoke(uint16 chainId, address spokeContractAddress) public {
        require(msg.sender == owner());
        registerSpokeContract(chainId, spokeContractAddress);
    }

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {
        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

    function completeDeposit(bytes calldata encodedMessage) public {
        
    }

    function completeWithdraw(bytes calldata encodedMessage) public {}

    function completeBorrow(bytes calldata encodedMessage) public {}

    function completeRepay(bytes calldata encodedMessage) public {}

    function completeLiquidation(bytes calldata encdoedMessage) public {}

    function repay() public {}

    function liquidate(address vault, address[] memory tokens) public {}

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

    function getWormholePayload(bytes calldata encodedMessage) internal returns (bytes memory) {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        verifySenderIsSpoke(parsed.emitterChainId, address(uint160(bytes20(parsed.emitterAddress))));

        require(!messageHashConsumed(parsed.hash), "message already confused");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    } 

    
}