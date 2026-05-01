pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/adapters/IOpalAdapterAaveV3.sol)

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Aave V3
/// @notice An OPAL Adapter which is a borrow position in an Aave V3 market.
/// That will be a single position with one or more collateral tokens and one debt token.
/// Note: This assumes there is no stable debt - so Aave > v3.2, or a fork for markets with no stable debt.
interface IOpalAdapterAaveV3 is IOpalAdapter {
    event ReferralCodeSet(uint16 code);
    event AavePoolUpdated(address indexed pool);
    event MaxLoanUtilizationRatioOnJoinSet(uint256 ratio);

    /****** IMMUTABLE GETTERS ******/

    /// @notice Aave pool addresses provider
    function aavePoolAddressProvider() external view returns (IPoolAddressesProvider);

    /// @notice The number of collateral tokens which can be used as collateral in this position
    function numCollateralTokens() external view returns (uint8);

    /// @notice The set of tokens which can be added as collateral in aave under the same position (with same e-mode).
    function collateralTokens() external view returns (address[] memory);

    /// @notice The matching set of Aave A Tokens matching the collateral tokens.
    function aaveATokens() external view returns (address[] memory result);

    /// @notice The token which is borrowed
    function loanToken() external view returns (address);

    /// @notice The Aave D Token representing the debt position
    function aaveDToken() external view returns (address);

    /****** ADMIN ******/

    /// @notice Update the reference to the aave pool (along with approvals) in case it ever changes
    function updateAavePool() external;

    /// @notice Set the Aave referral code
    function setReferralCode(uint16 code) external;

    /// @notice Allow the use of collateral token at the specified index as collateral within Aave
    function setUserUseReserveAsCollateral(address token, bool useAsCollateral) external;

    /// @notice Update the e-mode category for the pool
    function setEModeCategory(uint8 categoryId) external;

    /// @notice Set the maximum Utilization Ratio of the loan token allowed when
    /// joining into the vault. Specified in WAD.
    function setMaxLoanUtilizationRatioOnJoin(uint256 maxRatio) external;

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Supply an amount of `token` as collateral
    /// @dev Will revert if:
    ///       - This will breach the Aave supply cap
    ///       - The token reserve config is paused/frozen/etc in Aave
    ///       - There aren't enough collateral tokens in this contract
    /// @param token The collateral token. Not necessarily in the set of collateralTokens() since anyone
    ///              can donate from outside of this contract anyway
    /// @param amount The amount of collateral to supply. Pass `type(uint256).max` to supply the adapter's entire
    ///               balance of `token`
    /// @param minAmount Skip supplying collateral if the derived amount is less than this threshold.
    ///                  To avoid wasting gas for dust
    function supplyCollateral(address token, uint256 amount, uint256 minAmount) external returns (uint256 supplied);

    /// @notice Withdraw an amount of `token` collateral
    /// @dev Will revert if
    ///       - `amount` is greater than the account supplied collateral (unless set to `type(uint256).max`)
    ///       - If the LTV is above the 'max safe LTV'
    ///       - There isn't sufficient liquidity
    /// @param token The collateral token. Not necessarily in the set of collateralTokens() since anyone
    ///              can donate from outside of this contract anyway
    /// @param amount The amount of collateral to withdraw. Pass `type(uint256).max` to withdraw the adapter's entire
    ///               aToken balance corresponding to `token`
    /// @param recipient The address that will receive the collateral assets.
    function withdrawCollateral(address token, uint256 amount, address recipient) external returns (uint256 withdrawn);

    /// @notice Borrows `loanToken`
    /// @dev Will revert if
    ///       - There isn't sufficient liquidity
    ///       - This will breach the Aave borrow cap
    ///       - The token reserve config is paused/frozen/not borrowable/etc in Aave
    ///       - If the LTV is above the 'max safe LTV'
    /// @param amount The amount of `loanToken` to borrow.
    /// @param recipient The address that will receive the borrowed assets.
    function borrow(uint256 amount, address recipient) external;

    /// @notice Repay `loanToken`
    /// @dev Will revert if
    ///       - The token reserve config is paused/frozen/etc in Aave
    ///       - There aren't enough loanTokens in this contract
    /// @param amount The amount of `loanToken` to repay. Pass `type(uint256).max` to repay the adapter's entire
    ///               balance of `loanToken`. Amount actually repaid will be capped to the outstanding debt balance.
    /// @param minAmount Skip repaying debt if the derived amount is less than this threshold.
    ///                  To avoid wasting gas for dust
    function repay(uint256 amount, uint256 minAmount) external returns (uint256 repaid);

    /**
     * @notice Claim rewards from an aave rewards controller.
     * @param rewardsController The aave-v3-periphery RewardsController
     * @param assets The list of assets to check eligible distributions before claiming rewards
     * @param to The address that will be receiving the rewards
     * @return rewardsList List of addresses of the reward tokens
     * @return claimedAmounts List that contains the claimed amount per reward, following same order as "rewardList"
     */
    function claimAllRewards(address rewardsController, address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @notice Validate that the LTV of this contract is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `LtvOutOfRange`
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) external view;

    /// @notice Validate that the Utilization Ratio of the `loanToken` within Aave is
    /// is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `UtilizationRatioOutOfRange`
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view;

    /****** VIEWS ******/

    /// @notice The Aave pool contract
    function aavePool() external view returns (IAavePool);

    /// @notice The maximum Utilization Ratio of the loan token allowed when
    /// joining into the vault. Specified in WAD.
    function maxLoanUtilizationRatioOnJoin() external view returns (uint256);

    /// @notice The referral code used when supplying/borrowing in Aave
    function referralCode() external view returns (uint16);

    /// @notice Encode the immutable args for cloning
    function encodeImmutableArgs(
        address _aavePoolAddressProvider,
        address[] calldata _collateralTokens,
        address _loanToken
    ) external view returns (bytes memory);

    /// @notice Encode the initialization args
    function encodeInitArgs(address _initialOwner, uint8 _defaultEMode, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        view
        returns (bytes memory);

    /// @notice The current `loanToken` utilization ratio on Aave
    function currentLoanTokenUtilizationRatio() external view returns (uint256 utilizationRatio);

    struct AavePositionDetails {
        /// @notice The total collateral of this contract in the base currency (and decimals)
        /// used by the Aave price feed
        uint256 totalCollateralBase;

        /// @notice The total debt of this contract in the base currency (and decimals)
        /// used by the Aave price feed
        uint256 totalDebtBase;

        /// @notice The borrowing power left of this contract in the base currency (and decimals)
        /// used by the Aave price feed
        uint256 availableBorrowsBase;

        /// @notice The Loan-To-Value (LTV) where the position may be liquidated,
        /// given this account's collateral/debt/e-mode
        /// Represented in WAD
        uint256 liquidationLtv;

        /// @notice The maximum Loan-To-Value (LTV) that this adapter can safetly borrow up to,
        /// given this account's collateral/debt/e-mode
        /// Represented in WAD
        uint256 maxSafeLtv;

        /// @notice The current LTV of this contract
        /// Represented in WAD
        uint256 currentLtv;

        /// @notice The current health factor of this contract's position
        /// Represented in WAD
        uint256 healthFactor;
    }

    /// @notice Returns the Aave position details
    function positionDetails() external view returns (AavePositionDetails memory);

    /// @notice Metrics relevant the max collateral which can be supplied
    struct AssetSupplyMetrics {
        /// @notice Whether supplying has been disabled within Aave
        /// @dev true if the reserve asset is (!isActive || isFrozen || isPaused)
        bool supplyingDisabled;

        /// @notice The supply cap configured within Aave, in the underlying token decimals
        /// If no cap, this is type(uint256).max
        uint256 aaveSupplyCap;

        /// @notice The amount already supplied, in the underlying token decimals
        uint256 alreadySupplied;
    }

    /// @notice Metrics relevant the max collateral which can be withdrawn
    struct AssetWithdrawMetrics {
        /// @notice Whether withdrawing has been disabled within Aave
        /// @dev true if the reserve asset is (!isActive || isPaused)
        bool withdrawingDisabled;

        /// @notice The global amount of collateral supplied in Aave which hasn't already been borrowed
        uint256 availableSupply;
    }

    /// @notice Metrics relevant the max liability which can be borrowed
    struct LiabilityBorrowMetrics {
        /// @notice Whether borrowing has been disabled within Aave
        /// @dev true if the reserve asset is (!isActive || isFrozen || !borrowingEnabled || isPaused)
        bool borrowingDisabled;

        /// @notice The borrow cap as configured in Aave, in the underlying token decimals
        /// If no cap, this is type(uint256).max
        uint256 aaveBorrowCap;

        /// @notice The Origami policy cap taking `maxLoanUtilizationRatioOnJoin` into account.
        /// If no cap (if maxLoanUtilizationRatioOnJoin is set to 1e18), this is type(uint256).max
        uint256 joinBorrowCap;

        /// @notice The amount of debt already borrowed - includes accrued
        uint256 alreadyBorrowed;

        /// @notice The available liquidity (actual tokens) to borrow, ignoring any caps
        uint256 availableSupply;

        /// @notice If this position is in isolation mode, then will report the isolation mode debt ceiling
        /// @dev Zero if isolation mode not enabled. Same decimals as the borrow token
        uint256 isolationModeDebtCeiling;

        /// @notice If this position is in isolation mode, then this will report the amount already borrowed vs that cap
        /// @dev Zero if isolation mode not enabled. Same decimals as the borrow token
        uint256 isolationModeTotalDebt;
    }

    /// @notice Metrics relevant the max liability which can be repaid
    struct LiabilityRepayMetrics {
        /// @notice Whether repaying has been disabled within Aave
        /// @dev true if the reserve asset is (!isActive || isPaused)
        bool repayingDisabled;

        /// @notice The global amount of dToken supply in Aave which can be repaid
        uint256 alreadyBorrowed;
    }

    /// @notice Get the supply/borrow metrics relevant to join constraints
    function joinMetrics()
        external
        view
        returns (AssetSupplyMetrics[] memory supplyMetrics, LiabilityBorrowMetrics memory borrowMetrics);

    /// @notice Get the withdraw/repay metrics relevant to exit constraints
    function exitMetrics()
        external
        view
        returns (AssetWithdrawMetrics[] memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics);
}
