# Wormhole Cross-Chain Lending/Borrowing Example

## Objective
---

To use the Wormhole protocol to enable cross-chain borrowing and lending.

## Background
---

Borrow/lend platforms are one of the major DeFi applications, enabling users to permissionlessly deploy excess capital for passive yield generation or borrow against existing capital to capture new opportunities. Currently lending and borrowing pools exist independently across each blockchain, leading to fragmented liquidity and inefficiencies for protocols and potentially less favorable lending/borrowing rates for the protocol users.

Using Wormhole, a borrow/lend platform can become agnostic to the blockchain that users want to post collateral from, borrow from, or lend to.

## Goals
---

Implement a proof-of-concept, non-production example that allows:

**Borrowers**
- Deposit collateral from chainA and borrow tokens from chainB.
- Repay the borrowed loan (plus interest) on chainB and receive their collateral on chainA.

**Lenders**
- Deposit native assets on any chain.
- Redeem deposit (plus interest) on the chain they deposited on.

## Non-Goals
---

- Automatically relay messages across chains. The design assumes the borrow is always interested in submitting the message across chains in the depositing or repaying action.
- Produce a production-level ready protocol.

## Overview
---

This Wormhole Cross-chain Lending/Borrowing example enables a user to
- deposit BUSD on BNB as collateral and borrow WETH on Ethereum
- repay the WETH loan on Ethereum and get their BUSD collateral back on BNB.

## Detailed Design
---

To initiate a borrow position, the user flow for a user using BUSD on BNB as collateral for WETH on Ethereum is as follows:

1. User calls `addCollateral` to deposit BUSD into the BNB contract which will be reflected in the user's amount of deposited assets and total BUSD liquidity.
2. User calls `initiateBorrow` on BNB with the amount of WETH to borrow in Ethereum. This will calculate the maximum amount of WETH that the user can borrow based on the deposited amount of BUSD based on a collateralization ratio and generate a cross-chain message (VAA) to be redeemed through on Ethereum.
3. User calls `completeBorrow` on the Ethereum contract, giving as input the VAA generated in the previous step. The contract on Ethereum will verify the validity of the VAA and check if there is sufficient WETH liquidity for the user to borrow.
    - If there is sufficient WETH liquidity, the user is sent the amount of WETH requested which is reflected in the user's amount of borrowed assets and WETH liquidity.
    - If there is insufficient WETH liquidity, the contract on Ethereum will revert the borrow request and generate a VAA to be redeemed by the contract on BNB to allow the user to withdraw their collateral.

To repay an open borrow position, the user flow for a user repaying a WETH loan on Ethereum to get their BUSD collateral on BNB back is as follows: 
1. User calls `initiateRepay`or `initiateRepayInFull` to deposit WETH into the Ethereum contract which will update the user's amount of borrowed assets and total WETH liquidity as well as generate a VAA to be redeemed on BNB.
2. User calls `completeRepay` on the BNB contract, giving as input the VAA generated in the previous step. The contract on BNB will verify the validity of the VAA, update the user's amount of borrowed assets, and check if the loan has been repaid in full and within the defined grace period.
    - If the loan was not repaid within the defined grace period, a VAA is generated to identify this violation.
3. User calls `removeCollateral` or `removeCollateralInFull` to receive BUSD which will be reflected in the user's amount of deposited assets and total BUSD liquidity.

### API
---

**Borrower**
- `addCollateral(uint256 amount)`
- `removeCollateral(uint256 amount)`
- `removeCollateralInFull()`
- `initateBorrow(uint256 amount)`
- `completeBorrow(bytes calldata encodedVm)`
- `completeRevertBorrow(bytes calldata encodedVm)`
- `initiateRepay(uint256 amount)`
- `initiateRepayInFull()`
- `completeRepay(bytes calldata encodedVm)`

**Liquidator**
- `initiateLiquidationOnTargetChain(address accountToLiquidate)`
- `completeRepayOnBehalf(bytes calldata encodedVm)`

---

### Payloads

Borrow Message
```
uint8 payloadID                         // payloadID = 1
addreww borrower                        // address of borrower
address collateralAddress               // collateral information
address borrowAddress                   // borrow information
uint256 borrowAmount                    // amount borrowed
uint256 totalNoramlizedBorrowAmount     // amount borrowed normalized to the interest accrued
uint256 interestAccuralIndex            // interest accural on chain that collateral is deposited on
```

Revert Borrow Message
```
uint8 payloadID                         // payloadID = 2
addreww borrower                        // address of borrower
address collateralAddress               // collateral information
address borrowAddress                   // borrow information
uint256 borrowAmount                    // amount borrowed
uint256 sourceInterestAccuralIndex      // interest accural on chain that collateral is despoited on
```

Repay Message
```
uint8 payloadID                         // payloadID = 3
addreww borrower                        // address of borrower
address collateralAddress               // collateral information
address borrowAddress                   // borrow information
uint256 repayAmount                     // amount of collateral to repay
uint256 targetInterestAccuralIndex      // interest accural on chain that loan is taken on
uint256 repayTimestamp                  // time of repayment transaction
uint8 paidInFull                        // numeric toggle indicating if a loan is repaid in full
```

Liquidation Intent Message
```
uint8 payloadID                         // payloadID = 4
addreww borrower                        // address of borrower
address collateralAddress               // collateral information
address borrowAddress                   // borrow information
// TODO: add necesssary variables
```

## Future Work
---

This current proof-of-concept implements the cross-chain borrow capability that utilizes vaults on single chain. There are two main components of future development.

1. Multi-chain Vaults 
- Deposit two or more separate forms of collateral on two or more distinct chains.
2. Liquidation
- Initiate a liquidation process on the chain where collateral is deposited.
- Repay the borrowed amount on the chain that funds are borrowed from.
- Redeem the collateral on the chain that it is deposited on.