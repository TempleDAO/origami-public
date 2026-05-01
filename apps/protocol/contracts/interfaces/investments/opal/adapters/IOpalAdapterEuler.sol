pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/adapters/IOpalAdapterEuler.sol)

import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Euler
/// @notice An OPAL Adapter which is a borrow position in an Euler V2 market.
/// That will be a single position with exactly one collateral token and exactly one debt token.
interface IOpalAdapterEuler is IOpalAdapter {
    event MaxLoanUtilizationRatioOnJoinSet(uint256 ratio);

    /****** IMMUTABLE GETTERS ******/

    /// @notice The token which can be added as collateral in Euler.
    function collateralToken() external view returns (address);

    /// @notice The collateral vault to supply `collateralToken` into
    function collateralVault() external view returns (IEVault);

    /// @notice The token which is borrowed
    function loanToken() external view returns (address);

    /// @notice The borrow vault to borrow `loanToken` from
    function borrowVault() external view returns (IEVault);

    /****** ADMIN ******/

    /// @notice Set the maximum Utilization Ratio of the loan token allowed when
    ///         joining into the vault. Specified in WAD.
    function setMaxLoanUtilizationRatioOnJoin(uint256 maxRatio) external;

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Supply an amount of `token` as collateral
    /// @dev Will revert if:
    ///       - This will breach the Euler supply cap
    ///       - There aren't enough collateral tokens in this contract
    ///       - The OP_DEPOSIT operation is disabled in Euler
    ///       - The proxy implementation has been upgraded to a 'read only' (global Euler pause)
    ///       - May also revert if an Euler hook has been installed - depending on that hook
    /// @param amount The amount of collateral to supply. Pass `type(uint).max` to supply the adapter's entire
    ///               collateral balance.
    /// @param minAmount Skip supplying collateral if the derived amount is less than this threshold.
    ///                  To avoid wasting gas for dust
    function supplyCollateral(uint256 amount, uint256 minAmount) external returns (uint256 supplied);

    /// @notice Withdraw an amount of collateral
    /// @dev Will revert if:
    ///       - `amount` is greater than the account supplied collateral (unless set to `type(uint256).max`)
    ///       - If the LTV is above the 'max safe LTV'
    ///       - There isn't sufficient liquidity
    ///       - The OP_WITHDRAW or OP_REDEEM (for 'max') operation is disabled in Euler
    ///       - The proxy implementation has been upgraded to a 'read only' (global Euler pause)
    ///       - May also revert if an Euler hook has been installed - depending on that hook
    /// @param amount The amount of collateral to withdraw. Pass `type(uint).max` to withdraw the adapter's entire
    ///               aToken balance.
    /// @param recipient The address that will receive the collateral assets.
    function withdrawCollateral(uint256 amount, address recipient) external returns (uint256 withdrawn);

    /// @notice Borrow tokens and send to recipient
    /// @dev Will revert if:
    ///       - There isn't sufficient liquidity
    ///       - This will breach the Euler borrow cap
    ///       - If the LTV is above the 'max safe LTV'
    ///       - The OP_BORROW operation is disabled in Euler
    ///       - The proxy implementation has been upgraded to a 'read only' (global Euler pause)
    ///       - May also revert if an Euler hook has been installed - depending on that hook
    /// @param amount The amount of `loanToken` to borrow. Use `type(uint256).max` to borrow the max available liquidity
    ///               in Euler (not based on the account LTV). May revert if that 'max' takes the LTV over the 'max safe
    /// LTV' @param recipient The address that will receive the borrowed assets.
    function borrow(uint256 amount, address recipient) external returns (uint256 borrowedAmount);

    /// @notice Repay debt.
    /// @dev Will revert if:
    ///       - There aren't enough loanTokens in this contract
    ///       - The OP_REPAY operation is disabled in Euler
    ///       - The proxy implementation has been upgraded to a 'read only' (global Euler pause)
    ///       - May also revert if an Euler hook has been installed - depending on that hook
    /// @param amount The amount of `loanToken` to repay. Pass `type(uint).max` to repay the adapter's loan asset
    /// balance. Capped to the outstanding debt balance.
    /// @param minAmount Skip repaying debt if the derived amount is less than this threshold.
    ///                  This is useful to avoid wasting gas for dust.
    function repay(uint256 amount, uint256 minAmount) external returns (uint256 repaid);

    /// @notice Executes a series of bundler operations with deferred Euler health checks.
    /// @dev Normally, Euler checks account health after every operation (e.g. repay, withdraw),
    ///      which can make it impossible to reorder steps without using flash loans. By using
    ///      `callThroughEVC`, health checks are deferred until the very end of the execution.
    /// @param callbackData ABI-encoded list of `Call` structs representing the bundler actions to execute.
    function withDeferredEulerChecks(bytes calldata callbackData) external;

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @notice Validate that the LTV of this contract is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `LtvOutOfRange`
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) external view;

    /// @notice Validate that the Utilization Ratio of the `loanToken` within Aave is
    /// is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `UtilizationRatioOutOfRange`
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view;

    /****** VIEWS ******/

    /// @notice Encode the immutable args for cloning
    function encodeImmutableArgs(address _collateralVault, address _borrowVault)
        external
        view
        returns (bytes memory result);

    /// @notice Encode the initialization args
    function encodeInitArgs(address _initialOwner, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        view
        returns (bytes memory);

    /// @notice Get the supply/borrow metrics relevant to join constraints
    function joinMetrics()
        external
        view
        returns (AssetSupplyMetrics memory supplyMetrics, LiabilityBorrowMetrics memory borrowMetrics);

    /// @notice Get the withdraw/repay metrics relevant to exit constraints
    function exitMetrics()
        external
        view
        returns (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics);

    /// @notice The Euler vault connector
    function eulerEVC() external view returns (address);

    /// @notice Returns the current Euler position data details
    function positionDetails() external view returns (EulerPositionDetails memory);

    /// @notice The current `loanToken` utilization ratio on Euler
    function currentLoanTokenUtilizationRatio() external view returns (uint256 utilizationRatio);

    /// @notice Return whether any operations specified are disabled on an Euler vault
    /// An operation is considered disabled if the hookedOps has been set for that operation and the
    /// hook target is the zero address.
    /// @dev
    ///  - This is controlled by the governor of the vault, eg the curator
    ///  - For the operation definitions, see:
    ///    https://github.com/TempleDAO/origami/blob/bfae1720568ced38ec94686bdb70ab67952b2af2/apps/protocol/contracts/external/euler-vault-kit/Constants.sol#L35
    /// @param vault The Euler vault (collateral or debt)
    /// @param operationsBitMask The masked operations to check eg:
    ///                            `OP_WITHDRAW`: Check if the OP_WITHDRAW operation is disabled
    ///                            `OP_WITHDRAW | OP_REDEEM`: Check if EITHER the OP_WITHDRAW or OP_REDEEM
    ///                                                       operation has been disabled
    function areAnyVaultOperationsDisabled(IEVault vault, uint32 operationsBitMask) external view returns (bool);

    /// @notice The maximum UR on `join`
    function maxLoanUtilizationRatioOnJoin() external view returns (uint256);

    /// @notice Metrics relevant the max liability which can be borrowed
    struct LiabilityBorrowMetrics {
        /// @notice Whether borrowing has been disabled within Euler
        /// @dev true if vault OP_BORROW is set and `hookTarget` is address(0)
        bool borrowingDisabled;

        /// @notice The borrow cap as configured in the Euler vault, resolved to the underlying token decimals
        uint256 eulerBorrowCap;

        /// @notice The amount of debt already borrowed - includes accrued
        uint256 alreadyBorrowed;

        /// @notice This is borrowVault.cash() which is the borrow vault's total holdings of `asset` (loanToken)
        uint256 availableSupply;

        /// @notice The Origami policy cap taking `maxLoanUtilizationRatioOnJoin` into account.
        /// If no cap (if maxLoanUtilizationRatioOnJoin is set to 1e18), this is type(uint256).max
        uint256 joinBorrowCap;
    }

    /// @notice Metrics relevant the max collateral which can be supplied
    struct AssetSupplyMetrics {
        /// @notice Whether supplying has been disabled within Euler
        /// @dev true if vault OP_DEPOSIT is set and `hookTarget` is address(0)
        bool supplyingDisabled;

        /// @notice The supply cap configured within Euler vault, in the underlying token decimals
        /// If no cap, this is type(uint256).max
        uint256 eulerSupplyCap;

        /// @notice The amount already supplied, in the underlying token decimals
        uint256 alreadySupplied;
    }

    /// @notice Metrics relevant the max collateral which can be withdrawn
    struct AssetWithdrawMetrics {
        /// @notice Euler vault flag if withdrawing is disabled on vault
        /// @dev true if vault OP_WITHDRAW is set and `hookTarget` is address(0)
        bool withdrawingDisabled;

        /// @notice The global amount of collateral supplied in Euler which hasn't already been borrowed
        uint256 availableSupply;
    }

    /// @notice Metrics relevant the max liability which can be repaid
    struct LiabilityRepayMetrics {
        /// @notice Euler vault flag set if repaying is disabled
        /// @dev true if vault OP_REPAY is set and `hookTarget` is address(0)
        bool repayingDisabled;

        /// @notice The global amount of total debt that can be repaid
        uint256 totalDebt;
    }

    struct EulerPositionDetails {
        /// @notice The amount of collateral supplied
        uint256 supplied;

        /// @notice The amount of `loanToken` borrowed
        uint256 borrowed;

        /// @notice Value of collateral in units of account
        uint256 collateralValueInUnitOfAcct;

        /// @notice Value of liability in unit of account
        uint256 liabilityValueInUnitOfAcct;

        /// @notice The Loan-To-Value (LTV) where the position may be liquidated,
        /// given this account's debt/collateral
        /// Represented in WAD
        uint256 liquidationLtv;

        /// @notice The maximum Loan-To-Value (LTV) that this adapter can safely borrow up to,
        /// given this account's collateral & debt
        /// Represented in WAD
        uint256 maxSafeLtv;

        /// @notice The current LTV of this account
        /// Represented in WAD
        uint256 currentLtv;

        /// @notice The estimated health factor of this account's position
        uint256 healthFactor;
    }
}
