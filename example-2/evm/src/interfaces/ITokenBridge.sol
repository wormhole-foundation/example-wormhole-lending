// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenBridge {
    function transferTokens(
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        uint256 arbiterFee,
        uint32 nonce
    ) external payable returns (uint64 sequence);

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) external view returns (address);

    function transferTokensWithPayload(
      address token,
      uint256 amount,
      uint16 recipientChain,
      bytes32 recipient,
      uint32 nonce,
      bytes memory payload
    ) external payable returns (uint64);
    function completeTransferWithPayload(
        bytes memory encodedVm
    ) external returns (bytes memory);
}