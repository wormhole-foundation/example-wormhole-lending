// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../contracts/lendingHub/HubStructs.sol";

interface ITokenBridge {
    struct TransferWithPayload {
        uint8 payloadID;
        uint256 amount;
        bytes32 tokenAddress;
        uint16 tokenChain;
        bytes32 to;
        uint16 toChain;
        bytes32 fromAddress;
        bytes payload;
    }

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

    function chainId() external view returns (uint16);

    function wrapAndTransferETHWithPayload(
        uint16 recipientChain,
        bytes32 recipient,
        uint32 nonce,
        bytes memory payload
    ) external returns (uint64 sequence);

    function _wrapAndTransferETH(uint256 arbiterFee) external returns (HubStructs.TransferResult memory transferResult);

    // function WETH() public view returns (IWETH);
}