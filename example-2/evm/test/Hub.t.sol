// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Hub} from "../src/contracts/lendingHub/Hub.sol";
import {HubStructs} from "../src/contracts/lendingHub/HubStructs.sol";
// TODO: add wormhole interface and use fork-url w/ mainnet

contract HubTest is Test {

    Hub hub;
    function setUp() public {
        hub = new Hub(msg.sender, msg.sender, msg.sender, 1);
    }
    function testEncodeDepositMessage() public {

    }
    
}
