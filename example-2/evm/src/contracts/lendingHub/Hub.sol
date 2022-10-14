// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IWormhole.sol";

import "./HubSetters.sol";
import "./HubStructs.sol";
import "./HubMessages.sol";
import "./HubGetters.sol";

contract Hub is HubStructs, HubMessages, HubSetters, HubGetters {
    constructor(address wormhole_, address tokenBridge_, address mockPythAddress_, uint8 consistencyLevel_) {
        setOwner(_msgSender());
        setWormhole(wormhole_);
        setTokenBridge(tokenBridge_);
        setPyth(mockPythAddress_);

        setConsistencyLevel(consistencyLevel_);
    }

    function registerAsset(
        address assetAddress,
        uint256 collateralizationRatio,
        uint256 reserveFactor,
        bytes32 pythId,
        uint8 decimals
    ) public returns (uint64 sequence) {
        require(msg.sender == owner());

        AssetInfo memory registered_info = getAssetInfo(assetAddress);
        require(!registered_info.exists, "Asset already registered");

        allowAsset(assetAddress);

        AssetInfo memory info = AssetInfo({
            collateralizationRatio: collateralizationRatio,
            reserveFactor: reserveFactor,
            pythId: pythId,
            decimals: decimals,
            exists: true
        });

        registerAssetInfo(assetAddress, info);

        PayloadHeader memory payloadHeader = PayloadHeader({
            payloadID: 5,
            sender: address(this)
        });

        RegisterAssetMessage memory registerAssetMessage = RegisterAssetMessage({
            header: payloadHeader,
            assetAddress: assetAddress,
            collateralizationRatio: collateralizationRatio,
            reserveFactor: reserveFactor,
            pythId: pythId,
            decimals: decimals
        });

        // create WH message
        bytes memory serialized = encodeRegisterAssetMessage(registerAssetMessage);

        sequence = sendWormholeMessage(serialized);
    }

    function registerSpoke(uint16 chainId, address spokeContractAddress) public {
        require(msg.sender == owner());
        registerSpokeContract(chainId, spokeContractAddress);
    }

    function verifySenderIsSpoke(uint16 chainId, address sender) internal view {
        require(getSpokeContract(chainId) == sender, "Invalid spoke");
    }

    function computeSourceInterestFactor (
        uint256 secondsElapsed,
        uint256 deposited,
        uint256 borrowed,
        InterestRateModel memory interestRateModel
    ) internal pure returns (uint256) {
        if (deposited == 0) {
            return 0;
        }

        return (
            secondsElapsed
                * (interestRateModel.rateIntercept + (interestRateModel.rateCoefficientA * borrowed) / deposited)
        ) / 365 / 24 / 60 / 60;
    }

    function updateAccrualIndices(address assetAddress) internal {
        uint256 lastActivityBlockTimestamp = getLastActivityBlockTimestamp(assetAddress);
        uint256 secondsElapsed = block.timestamp - lastActivityBlockTimestamp;

        uint256 deposited = getTotalAssetsDeposited(assetAddress);
        uint256 borrowed = getTotalAssetsBorrowed(assetAddress);

        setLastActivityBlockTimestamp(assetAddress, block.timestamp);

        InterestRateModel memory interestRateModel = getInterestRateModel(assetAddress);

        uint256 interestFactor = computeSourceInterestFactor(secondsElapsed, deposited, borrowed, interestRateModel);

        AccrualIndices memory accrualIndices = getInterestAccrualIndices(assetAddress);
        accrualIndices.borrowed += interestFactor;
        accrualIndices.deposited += (interestFactor * borrowed) / deposited;
        accrualIndices.lastBlock = block.timestamp;

        setInterestAccrualIndices(assetAddress, accrualIndices);
    }

    /*
    function updateAccrualIndices(address[] assetAddresses) internal {
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            address assetAddress = assetAddresses[i];

            updateAccrualIndices(assetAddress);
        }
    }*/

    function completeDeposit(bytes calldata encodedMessage) public {

        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        DepositPayload memory params = decodeDepositPayload(vmPayload);

        deposit(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeWithdraw(bytes calldata encodedMessage) public {

        WithdrawPayload memory params = decodeWithdrawPayload(getWormholePayload(encodedMessage));

        withdraw(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeBorrow(bytes calldata encodedMessage) public {

        BorrowPayload memory params = decodeBorrowPayload(getWormholePayload(encodedMessage));

        borrow(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function completeRepay(bytes calldata encodedMessage) public {

        bytes memory vmPayload = tokenBridge().completeTransferWithPayload(encodedMessage);

        RepayPayload memory params = decodeRepayPayload(vmPayload);
        
        repay(params.header.sender, params.assetAddress, params.assetAmount);
    }

    function deposit(address depositor, address assetAddress, uint256 amount) internal {
        // TODO: What to do if this fails?

        checkValidAddress(assetAddress);

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        // calculate the normalized amount and store in the vault
        // update the global contract state with normalized amount
        VaultAmount memory vaultAmounts = getVaultAmounts(depositor, assetAddress);
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedDeposit = normalizeAmount(amount, indices.deposited);

        vaultAmounts.deposited += normalizedDeposit;
        globalAmounts.deposited += normalizedDeposit;

        setVaultAmounts(depositor, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);
    }

    

    function withdraw(address withdrawer, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // recheck if withdraw is valid given up to date prices? bc the prices can move in the time for VAA to come
        require(allowedToWithdraw(withdrawer, assetAddress, amount), "Not enough in vault");

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(withdrawer, assetAddress);
        vaultAmounts.deposited -= normalizedAmount;
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.deposited -= normalizedAmount;

        setVaultAmounts(withdrawer, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);

        transferTokens(withdrawer, assetAddress, amount);
    }

    function borrow(address borrower, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // recheck if borrow is valid given up to date prices? bc the prices can move in the time for VAA to come
        require(allowedToBorrow(borrower, assetAddress, amount), "Not enough in vault");

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.deposited);

        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(borrower, assetAddress);
        vaultAmounts.borrowed += normalizedAmount;
        // update state for global
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed += normalizedAmount;

        setVaultAmounts(borrower, assetAddress, vaultAmounts);
        setGlobalAmounts(assetAddress, globalAmounts);

        // TODO: token transfers
        transferTokens(borrower, assetAddress, amount);
    }

    function repay(address repayer, address assetAddress, uint256 amount) internal {
        checkValidAddress(assetAddress);

        // update the interest accrual indices
        updateAccrualIndices(assetAddress);

        // calculate the normalized amount and store in the vault and global
        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(amount, indices.borrowed);
        // update state for vault
        VaultAmount memory vaultAmounts = getVaultAmounts(repayer, assetAddress);
        vaultAmounts.borrowed -= normalizedAmount;
        // update global state
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        globalAmounts.borrowed -= normalizedAmount;


    }

    function transferTokens(address receiver, address assetAddress, uint256 amount) internal {
        //tokenBridge().transferTokensWithPayload(assetAddress, amount, recipientChain, recipient, nonce, payload);
    }


    function liquidation(address vault, address[] memory assetRepayAddresses, uint256[] memory assetRepayAmounts, address[] memory assetReceiptAddresses, uint256[] memory assetReceiptAmounts) public {
        // check if asset addresses all valid
        // TODO: eventually check all addresses in one function checkValidAddresses that checks for no duplicates also
        for(uint i=0; i<assetRepayAddresses.length; i++){
            checkValidAddress(assetRepayAddresses[i]);
        }
        for(uint i=0; i<assetReceiptAddresses.length; i++){
            checkValidAddress(assetReceiptAddresses[i]);
        }

        // update the interest accrual indices
        // TODO: Make more efficient
        address[] memory allowList = getAllowList();
        for(uint i=0; i<allowList.length; i++){
            updateAccrualIndices(allowList[i]);
        }

        // check if intended liquidation is valid
        allowedToLiquidate(vault, assetRepayAddresses, assetRepayAmounts, assetReceiptAddresses, assetReceiptAmounts);

        // for repay assets update amounts for vault and global
        for(uint i=0; i<assetRepayAddresses.length; i++){
            address assetAddress = assetRepayAddresses[i];
            uint256 assetAmount = assetRepayAmounts[i];

            AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(assetAmount, indices.borrowed);
            // update state for vault
            VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
            // require that amount paid back <= amount borrowed
            uint256 denormalizedBorrowedAmount = denormalizeAmount(vaultAmounts.borrowed, indices.borrowed);
            require(denormalizedBorrowedAmount >= assetAmount, "cannot repay more than has been borrowed");
            vaultAmounts.borrowed -= normalizedAmount;
            // update global state
            VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
            globalAmounts.borrowed -= normalizedAmount;

            setVaultAmounts(vault, assetAddress, vaultAmounts);
            setGlobalAmounts(assetAddress, globalAmounts);
        }

        // for received assets update amounts for vault and global
        for (uint256 i=0; i<assetReceiptAddresses.length; i++) {
            address assetAddress = assetReceiptAddresses[i];
            uint256 assetAmount = assetReceiptAmounts[i];

            AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

            uint256 normalizedAmount = normalizeAmount(assetAmount, indices.deposited);
            // update state for vault
            VaultAmount memory vaultAmounts = getVaultAmounts(vault, assetAddress);
            // require that amount received <= amount deposited
            uint256 denormalizedDepositedAmount = denormalizeAmount(vaultAmounts.deposited, indices.deposited);
            require(denormalizedDepositedAmount >= assetAmount, "cannot take out more collateral than vault has deposited");
            vaultAmounts.deposited -= normalizedAmount;
            // update global state
            VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
            globalAmounts.deposited -= normalizedAmount;

            setVaultAmounts(vault, assetAddress, vaultAmounts);
            setGlobalAmounts(assetAddress, globalAmounts);
        }

        // send repay tokens from liquidator to contract
        for(uint i=0; i<assetRepayAddresses.length; i++){
            address assetAddress = assetRepayAddresses[i];
            uint256 assetAmount = assetRepayAmounts[i];

            SafeERC20.safeTransferFrom(
                IERC20(assetAddress),
                msg.sender,
                address(this),
                assetAmount
            );
        }

        // send receive tokens from contract to liquidator
        for(uint i=0; i<assetReceiptAddresses.length; i++){
            address assetAddress = assetReceiptAddresses[i];
            uint256 assetAmount = assetReceiptAmounts[i];

            SafeERC20.safeTransferFrom(
                IERC20(assetAddress),
                address(this),
                msg.sender,
                assetAmount
            );
        }
    }

    function sendWormholeMessage(bytes memory payload) internal returns (uint64 sequence) {
        sequence = wormhole().publishMessage(
            0, // nonce
            payload,
            consistencyLevel()
        );
    }

    function getWormholePayload(bytes calldata encodedMessage) internal returns (bytes memory) {
        (IWormhole.VM memory parsed, bool valid, string memory reason) = wormhole().parseAndVerifyVM(encodedMessage);
        require(valid, reason);

        verifySenderIsSpoke(parsed.emitterChainId, address(uint160(bytes20(parsed.emitterAddress))));

        require(!messageHashConsumed(parsed.hash), "message already confused");
        consumeMessageHash(parsed.hash);

        return parsed.payload;
    }
}
