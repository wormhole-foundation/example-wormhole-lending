// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IWormhole.sol";
import "./libraries/external/BytesLib.sol";

import "./CrossChainBorrowLendStructs.sol";
import "./CrossChainBorrowLendGetters.sol";
import "./CrossChainBorrowLendMessages.sol";

contract CrossChainBorrowLend is
    CrossChainBorrowLendGetters,
    CrossChainBorrowLendMessages
{
    constructor(
        address wormholeContractAddress_,
        uint8 consistencyLevel_,
        address mockPythAddress_,
        uint16 targetChainId_,
        bytes32 targetContractAddress_,
        address collateralAsset_,
        bytes32 collateralAssetPythId_,
        uint256 collateralizationRatio_,
        address borrowingAsset_,
        bytes32 borrowingAssetPythId_
    ) {
        // contract owner
        state.owner = _msgSender();

        // wormhole
        state.wormholeContractAddress = wormholeContractAddress_;
        state.consistencyLevel = consistencyLevel_;

        state.mockPythAddress = mockPythAddress_;

        state.targetChainId = targetChainId_;
        state.targetContractAddress = targetContractAddress_;

        state.collateralAssetAddress = collateralAsset_;
        state.collateralizationRatio = collateralizationRatio_;
        state.collateralizationRatioPrecision = 1e8; // fixed

        state.borrowingAssetAddress = borrowingAsset_;

        // interest rate parameters
        state.interestRateModel.ratePrecision = 1e18;
        state.interestRateModel.rateIntercept = 2e16; // 2%
        state.interestRateModel.rateCoefficientA = 0;

        // Price index of 1 with the current precision is 1e18
        // since this is the precision of our value.
        state.collateralPriceIndexPrecision = 1e18;
        state.collateralPriceIndex = 1e18;

        // pyth asset IDs
        state.collateralAssetPythId = collateralAssetPythId_;
        state.borrowingAssetPythId = borrowingAssetPythId_;
    }

    function supply(uint256 amount) public {
        require(amount > 0, "nothing to deposit");

        // update current price index
        updateCollateralPriceIndex();

        // update state for supplier
        uint256 normalizedAmount = normalizeAmount(amount);
        state.accountAssets[_msgSender()].deposited += normalizedAmount;
        state.totalAssets.deposited += normalizedAmount;

        SafeERC20.safeTransferFrom(
            collateralToken(),
            _msgSender(),
            address(this),
            amount
        );
    }

    function computeInterestProportion(
        uint256 secondsElapsed,
        uint256 intercept,
        uint256 coefficient
    ) internal view returns (uint256) {
        return
            (secondsElapsed *
                (intercept +
                    (coefficient * state.totalAssets.borrowed) /
                    state.totalAssets.deposited)) /
            365 /
            24 /
            60 /
            60;
    }

    function updateCollateralPriceIndex() internal {
        // TODO: change to block.number?
        uint256 secondsElapsed = block.timestamp -
            state.lastActivityBlockTimestamp;

        if (secondsElapsed == 0) {
            // nothing to do
            return;
        }
        state.lastActivityBlockTimestamp = block.timestamp;

        state.collateralPriceIndex =
            (state.collateralPriceIndex *
                computeInterestProportion(
                    secondsElapsed,
                    state.interestRateModel.rateIntercept,
                    state.interestRateModel.rateCoefficientA
                )) /
            state.interestRateModel.ratePrecision;
    }

    function initiateBorrow(uint256 amount) public returns (uint64 sequence) {
        require(amount > 0, "nothing to borrow");

        // For EVMs, same private key will be used for borrowing-lending activity.
        // When introducing other chains (e.g. Cosmos), need to do wallet registration
        // so we can access a map of a non-EVM address based on this EVM borrower
        NormalizedAmounts memory normalizedAmounts = state.accountAssets[
            _msgSender()
        ];

        // Need to calculate how much someone can borrow
        (
            uint64 collateralAssetPriceInUSD,
            uint64 borrowAssetPriceInUSD
        ) = getOraclePrices();

        // update current price index
        updateCollateralPriceIndex();

        uint256 maxAllowedToBorrow = (denormalizeAmount(
            normalizedAmounts.deposited
        ) *
            state.collateralizationRatio *
            collateralAssetPriceInUSD *
            10**borrowTokenDecimals()) /
            (state.collateralizationRatioPrecision *
                borrowAssetPriceInUSD *
                10**collateralTokenDecimals()) -
            denormalizeAmount(normalizedAmounts.borrowed);
        require(amount < maxAllowedToBorrow, "amount >= maxAllowedToBorrow");

        // update state for borrower
        uint256 normalizedAmount = normalizeAmount(amount);
        state.accountAssets[_msgSender()].borrowed += normalizedAmount;
        state.totalAssets.borrowed += normalizedAmount;

        // construct wormhole message
        MessageHeader memory header = MessageHeader({
            payloadID: uint8(1),
            borrower: _msgSender(),
            collateralAddress: state.collateralAssetAddress,
            borrowAddress: state.borrowingAssetAddress
        });

        sequence = sendWormholeMessage(
            encodeBorrowMessage(
                BorrowMessage({
                    header: header,
                    borrowAmount: amount,
                    totalNormalizedBorrowAmount: normalizedAmount
                })
            )
        );
    }

    function completeBorrow(bytes calldata encodedVm)
        public
        returns (uint64 sequence)
    {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedVm);
        require(valid, reason);

        // verify emitter
        require(verifyEmitter(parsed), "invalid emitter");

        // completed (replay protection)
        consumeMessageHash(parsed.hash);

        // decode
        BorrowMessage memory params = decodeBorrowMessage(parsed.payload);

        // correct assets?
        require(verifyAssetMetaFromBorrow(params), "invalid asset metadata");

        // TODO: check if we can release funds and transfer to borrower
        if (params.borrowAmount < denormalizeAmount(normalizedLiquidity())) {
            // construct wormhole message
            // switch the borrow and collateral addresses for the target chain
            MessageHeader memory header = MessageHeader({
                payloadID: uint8(2),
                borrower: _msgSender(),
                collateralAddress: state.borrowingAssetAddress,
                borrowAddress: state.collateralAssetAddress
            });

            sequence = sendWormholeMessage(
                encodeRevertBorrowMessage(
                    RevertBorrowMessage({
                        header: header,
                        borrowAmount: params.borrowAmount
                    })
                )
            );
        } else {
            // update current price index
            updateCollateralPriceIndex();

            // update state for borrower
            uint256 normalizedAmount = normalizeAmount(params.borrowAmount);
            state.totalAssets.deposited -= normalizedAmount;

            // save the total normalized borrow amount for repayments
            state.accountAssets[_msgSender()].borrowed = params
                .totalNormalizedBorrowAmount;

            // finally transfer
            SafeERC20.safeTransferFrom(
                collateralToken(),
                address(this),
                _msgSender(),
                params.borrowAmount
            );

            // no wormhole message. zero == success
            sequence = 0;
        }
    }

    function repay(uint256 amount) public returns (uint64 sequence) {
        require(amount > 0, "nothing to repay");

        // For EVMs, same private key will be used for borrowing-lending activity.
        // When introducing other chains (e.g. Cosmos), need to do wallet registration
        // so we can access a map of a non-EVM address based on this EVM borrower
        NormalizedAmounts memory normalizedAmounts = state.accountAssets[
            _msgSender()
        ];

        // construct wormhole message
        MessageHeader memory header = MessageHeader({
            payloadID: uint8(3),
            borrower: _msgSender(),
            collateralAddress: state.borrowingAssetAddress,
            borrowAddress: state.collateralAssetAddress
        });

        sequence = sendWormholeMessage(
            encodeRepayMessage(
                RepayMessage({header: header, repayAmount: amount})
            )
        );
    }

    function completeRepay(bytes calldata encodedVm)
        public
        returns (uint64 sequence)
    {
        (
            IWormhole.VM memory parsed,
            bool valid,
            string memory reason
        ) = wormhole().parseAndVerifyVM(encodedVm);
        require(valid, reason);

        // verify emitter
        require(verifyEmitter(parsed), "invalid emitter");

        // completed (replay protection)
        consumeMessageHash(parsed.hash);

        // decode
        RepayMessage memory params = decodeRepayMessage(parsed.payload);

        // correct assets?
        require(verifyAssetMetaFromRepay(params), "invalid asset metadata");

        // TODO: do something meaningful here
        sequence = 0;
    }

    function sendWormholeMessage(bytes memory payload)
        internal
        returns (uint64 sequence)
    {
        sequence = IWormhole(state.wormholeContractAddress).publishMessage(
            0, // nonce
            payload,
            state.consistencyLevel
        );
    }

    function verifyEmitter(IWormhole.VM memory parsed)
        internal
        view
        returns (bool)
    {
        return
            parsed.emitterAddress == state.targetContractAddress &&
            parsed.emitterChainId == state.targetChainId;
    }

    function verifyAssetMetaFromBorrow(BorrowMessage memory params)
        internal
        view
        returns (bool)
    {
        return
            params.header.collateralAddress == state.borrowingAssetAddress &&
            params.header.borrowAddress == state.collateralAssetAddress;
    }

    function verifyAssetMetaFromRepay(RepayMessage memory params)
        internal
        view
        returns (bool)
    {
        return
            params.header.collateralAddress == state.collateralAssetAddress &&
            params.header.borrowAddress == state.borrowingAssetAddress;
    }

    function consumeMessageHash(bytes32 vmHash) internal {
        state.consumedMessages[vmHash] = true;
    }
}
