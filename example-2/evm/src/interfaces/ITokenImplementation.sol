// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenImplementation {
    function nativeContract() external view returns (bytes32);

    function chainId() external view returns (uint16);
}
