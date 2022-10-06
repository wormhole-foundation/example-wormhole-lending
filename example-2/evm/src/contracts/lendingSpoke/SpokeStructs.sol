// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract SpokeStructs {
    struct LiquidationRepay {
        address repayToken;
        uint256 amount;
    }

    struct LiquidationReceipt {
        address tokenToLiquidate;
        uint256 amount;
    }
}