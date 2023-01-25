// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../HubSpokeStructs.sol";
import "./HubGetters.sol";
import "./HubSetters.sol";
import "./HubPriceUtilities.sol";
import "./HubInterestUtilities.sol";
import "./HubWormholeUtilities.sol";

contract HubChecks is HubSpokeStructs, HubGetters, HubSetters, HubInterestUtilities, HubPriceUtilities, HubWormholeUtilities {
    /** @notice Check if vaultOwner is allowed to withdraw assetAmount of assetAddress from their vault
     * 
     * @param vaultOwner - The address of the owner of the vault
     * @param assetAddress - The address of the relevant asset
     * @param assetAmount - The amount of the relevant asset
     * Only returns (otherwise reverts) if this withdrawal keeps the vault at a nonnegative notional value (worth >= $0 according to Pyth prices)
     * (where the deposit values are divided by the deposit collateralization ratio and the borrow values are multiplied by the borrow collateralization ratio)
     * and also if there is enough asset in the vault to complete the withdrawal
     * and also if there is enough asset in the total reserve of the protocol to complete the withdrawal
     */
    function checkAllowedToWithdraw(address vaultOwner, address assetAddress, uint256 assetAmount) internal view {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(assetAmount, indices.deposited, Round.UP);

        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vaultOwner, true);

        checkVaultHasAssets(vaultOwner, assetAddress, normalizedAmount);
        checkProtocolGloballyHasAssets(assetAddress, normalizedAmount);
        require(
            vaultDepositedValue
                >= vaultBorrowedValue
                    + normalizedAmount * indices.deposited * getPriceCollateral(assetAddress)
                        * (10 ** (getMaxDecimals() - assetInfo.decimals)) * assetInfo.collateralizationRatioDeposit,
            "Vault is undercollateralized if this withdraw goes through"
        );
    }

    /** 
     * @notice Check if vaultOwner is allowed to borrow assetAmount of assetAddress from their vault
     *
     * @param vaultOwner - The address of the owner of the vault
     * @param assetAddress - The address of the relevant asset
     * @param assetAmount - The amount of the relevant asset
     * Only returns (otherwise reverts) if this borrow keeps the vault at a nonnegative notional value (worth >= $0 according to Pyth prices)
     * (where the deposit values are divided by the deposit collateralization ratio and the borrow values are multiplied by the borrow collateralization ratio)
     * and also if there is enough asset in the total reserve of the protocol to complete the borrow
     */
    function checkAllowedToBorrow(address vaultOwner, address assetAddress, uint256 assetAmount) internal view {
        AssetInfo memory assetInfo = getAssetInfo(assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint256 normalizedAmount = normalizeAmount(assetAmount, indices.borrowed, Round.UP);

        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vaultOwner, true);

        checkProtocolGloballyHasAssets(assetAddress, normalizedAmount);
        require(
            (vaultDepositedValue)
                >= vaultBorrowedValue
                    + normalizedAmount * indices.borrowed * getPriceDebt(assetAddress) * assetInfo.collateralizationRatioBorrow
                        * (10 ** (getMaxDecimals() - assetInfo.decimals)),
            "Vault is undercollateralized if this borrow goes through"
        );
    }

    /**
     * @notice Check if vaultOwner is allowed to repay assetAmount of assetAddress to their vault; they must have outstanding borrows of at least assetAmount for assetAddress to enable repayment
     * 
     * @param vaultOwner - The address of the owner of the vault
     * @param assetAddress - The address of the relevant asset
     * @param assetAmount - The amount of the relevant asset
     * @return {bool} True or false depending on if the outstanding borrows for this assetAddress >= assetAmount
     */
    function allowedToRepay(address vaultOwner, address assetAddress, uint256 assetAmount)
        internal
        view
        returns (bool)
    {
        VaultAmount memory vaultAmount = getVaultAmounts(vaultOwner, assetAddress);

        AccrualIndices memory indices = getInterestAccrualIndices(assetAddress);

        uint8 decimals = getAssetInfo(assetAddress).decimals;

        uint256 denormalizedAmount = denormalizeAmount(vaultAmount.borrowed, indices.borrowed, Round.UP);

        // confirm that the amount filtered by token bridge decimal controls is less than the rounded up version of the vault's denormalized outstanding borrow. This allows vault owner to always be able to fully repay outstanding borrows.
        bool check = normalizeAmountTokenBridge(denormalizedAmount, decimals, Round.UP) >= normalizeAmountTokenBridge(assetAmount, decimals, Round.DOWN);

        return check;
    }

    /** 
     * @notice Check if vaultOwner is allowed to, for each i, repay assetRepayAmounts[i] of the asset at assetRepayAddresses[i] to the vault at 'vault',
     * and receive from the vault, for each i, assetReceiptAmounts[i] of the asset at assetReceiptAddresses[i]. Uses the Pyth prices to see if this liquidation should be allowed
     * 
     * @param vaultOwner - The address of the owner of the vault
     * @param assetRepayAddresses - The array of addresses of the assets being repayed
     * @param assetRepayAmounts - The array of amounts of each asset in assetRepayAddresses
     * @param assetReceiptAddresses - The array of addresses of the assets being repayed
     * @param assetReceiptAmounts - The array of amounts of each asset in assetRepayAddresses
     */
    function checkAllowedToLiquidate(
        address vaultOwner,
        address[] memory assetRepayAddresses,
        uint256[] memory assetRepayAmounts,
        address[] memory assetReceiptAddresses,
        uint256[] memory assetReceiptAmounts
    ) internal view {
        (uint256 vaultDepositedValue, uint256 vaultBorrowedValue) = getVaultEffectiveNotionals(vaultOwner, true);

        require(vaultDepositedValue < vaultBorrowedValue, "vault not underwater");

        (, uint256 vaultBorrowedTrueValue) = getVaultEffectiveNotionals(vaultOwner, false);

        uint256 notionalRepaid = 0;
        uint256 notionalReceived = 0;

        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            address asset = assetRepayAddresses[i];
            AccrualIndices memory indices = getInterestAccrualIndices(asset);

            AssetInfo memory assetInfo = getAssetInfo(asset);

            uint256 normalizedAmount = normalizeAmount(assetRepayAmounts[i], indices.borrowed, Round.DOWN);

            require(allowedToRepay(vaultOwner, asset, assetRepayAmounts[i]), "cannot repay more than has been borrowed");

            notionalRepaid +=
                normalizedAmount * indices.borrowed * getPrice(asset) * 10 ** (getMaxDecimals() - assetInfo.decimals);
        }

        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            address asset = assetReceiptAddresses[i];
            AccrualIndices memory indices = getInterestAccrualIndices(asset);

            AssetInfo memory assetInfo = getAssetInfo(asset);

            uint256 normalizedAmount = normalizeAmount(
                assetReceiptAmounts[i], // amount
                indices.deposited,
                Round.UP
            );

            checkVaultHasAssets(vaultOwner, asset, normalizedAmount);

            checkProtocolGloballyHasAssets(asset, normalizedAmount);

            notionalReceived +=
                normalizedAmount * indices.deposited * getPrice(asset) * 10 ** (getMaxDecimals() - assetInfo.decimals);
        }

        // safety check to ensure liquidator receives greater than or equal to the amount they pay
        require(notionalReceived >= notionalRepaid, "Liquidator receipt less than amount they repaid");

        // check to ensure that amount of debt repaid <= maxLiquidationPortion * amount of debt / liquidationPortionPrecision
        require(
            notionalRepaid 
                <= (getMaxLiquidationPortion() * vaultBorrowedTrueValue) / getMaxLiquidationPortionPrecision(),
            "Liquidator cannot claim more than maxLiquidationPortion of the total debt of the vault"
        );

        // check if notional received <= notional repaid * max liquidation bonus
        require(
            notionalReceived <= (getMaxLiquidationBonus() * notionalRepaid) / getCollateralizationRatioPrecision(),
            "Liquidator receiving too much value"
        );
    }

    /**
     * @notice Checks if the vault 'vault' has greater than or equal to normalizedAmount of the asset at assetAddress
     *
     * @param vault - the address of the vault to be checked
     * @param assetAddress - the address of the relevant asset
     * @param normalizedAmount - an arbitrary integer
     */
    function checkVaultHasAssets(address vault, address assetAddress, uint256 normalizedAmount) internal view {
        VaultAmount memory amounts = getVaultAmounts(vault, assetAddress);
        require(amounts.deposited >= amounts.borrowed + normalizedAmount, "Vault does not have required assets");
    }

    /**
     * @notice Checks if the protocol globally has greater than or equal to normalizedAmount of the asset at assetAddress
     *
     * @param assetAddress - the address of the relevant asset
     * @param normalizedAmount - an arbitrary integer
     */
    function checkProtocolGloballyHasAssets(address assetAddress, uint256 normalizedAmount) internal view {
        VaultAmount memory globalAmounts = getGlobalAmounts(assetAddress);
        require(
            globalAmounts.deposited >= globalAmounts.borrowed + normalizedAmount,
            "Global supply does not have required assets"
        );
    }

    /**
     * @notice Checks if the inputs for a liquidation are valid
     * Specifically, checks if each address is a registered asset
     * and both address arrays do not contain duplicate addresses
     *
     * @param assetRepayAddresses - The array of addresses of the assets being repayed
     * @param assetRepayAmounts - The array of amounts of each asset in assetRepayAddresses
     * @param assetReceiptAddresses - The array of addresses of the assets being repayed
     * @param assetReceiptAmounts - The array of amounts of each asset in assetRepayAddresses
     */
    function checkLiquidationInputsValid(
        address[] memory assetRepayAddresses,
        uint256[] memory assetRepayAmounts,
        address[] memory assetReceiptAddresses,
        uint256[] memory assetReceiptAmounts
    ) internal view {
        for (uint256 i = 0; i < assetRepayAddresses.length; i++) {
            checkValidAddress(assetRepayAddresses[i]);
        }
        for (uint256 i = 0; i < assetReceiptAddresses.length; i++) {
            checkValidAddress(assetReceiptAddresses[i]);
        }
        checkDuplicates(assetRepayAddresses);
        checkDuplicates(assetReceiptAddresses);

        require(assetRepayAddresses.length == assetRepayAmounts.length, "Repay array lengths do not match");
        require(assetReceiptAddresses.length == assetReceiptAmounts.length, "Repay array lengths do not match");
    }

    /**
     * @notice Check if an address has been registered on the Hub yet (through the registerAsset function)
     * Errors out if assetAddress has not been registered yet
     * @param assetAddress - The address to be checked
     */
    function checkValidAddress(address assetAddress) internal view {
        // check if asset address is allowed
        AssetInfo memory registeredInfo = getAssetInfo(assetAddress);
        require(registeredInfo.exists, "Unregistered asset");
    }

    /**
     * @notice Checks if the array of addresses has duplicate addresses
     * @param assetAddresses - The address array to be checked
     */
    function checkDuplicates(address[] memory assetAddresses) internal pure {
        // check if asset address array contains duplicates
        for (uint256 i = 0; i < assetAddresses.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                require(assetAddresses[i] != assetAddresses[j], "Address array has duplicate addresses");
            }
        }
    }
}
