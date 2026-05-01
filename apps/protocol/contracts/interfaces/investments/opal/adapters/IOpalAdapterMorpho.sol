pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/adapters/IOpalAdapterMorpho.sol)

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import {
    IMorphoSupplyCollateralCallback,
    IMorphoRepayCallback
} from "@morpho-org/morpho-blue/src/interfaces/IMorphoCallbacks.sol";

import {
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IOracle as IMorphoOracle } from "@morpho-org/morpho-blue/src/interfaces/IOracle.sol";

/// @title Origami Portfolio of Assets and Liabilities (OPAL) Adapter - Morpho
/// @notice An OPAL Adapter which is a borrow position in a single Morpho market, so one asset token and one liability
/// token
interface IOpalAdapterMorpho is IOpalAdapter, IMorphoSupplyCollateralCallback, IMorphoRepayCallback {
    event MaxSafeLtvSet(uint256 maxSafeLtv);
    event MaxLoanUtilizationRatioOnJoinSet(uint256 ratio);

    /****** IMMUTABLE GETTERS ******/

    /// @notice The morpho singleton contract
    function morpho() external view returns (IMorpho);

    /// @notice The token supplied as collateral
    function collateralToken() external view returns (address);

    /// @notice The token which is borrowed
    function loanToken() external view returns (address);

    /// @notice The Morpho oracle used for the target market
    function morphoOracle() external view returns (IMorphoOracle);

    /// @notice The Morpho Interest Rate Model used for the target market
    function morphoIrm() external view returns (address);

    /// @notice The Morpho Liquidation LTV for the target market
    function morphoLltv() external view returns (uint256);

    /// @notice The derived Morpho market ID given the market parameters
    function morphoMarketId() external view returns (MorphoMarketId);

    /****** ADMIN ******/

    /// @notice Set the max LTV we will allow when borrowing or withdrawing collateral.
    /// @dev The morpho LTV is the liquidation LTV only, we don't want to allow up to that limit
    /// so we set a more restrictive 'safe' LTV'. Specified in WAD.
    function setMaxSafeLtv(uint256 _maxSafeLtv) external;

    /// @notice Set the maximum Utilization Ratio of the loan token allowed when
    /// joining into the vault. Specified in WAD.
    function setMaxLoanUtilizationRatioOnJoin(uint256 maxRatio) external;

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Supply an amount of `collateralToken` as collateral
    /// @dev Will revert if:
    ///       - There aren't enough collateralTokens in this contract
    /// @param amount The amount of collateral to supply. Pass `type(uint).max` to supply the adapter's entire
    ///               balance of `collateralToken`.
    /// @param minAmount Skip supplying collateral if the derived amount is less than this threshold.
    ///                  To avoid wasting gas for dust
    /// @param callbackData can be provided as abi encoded OrigamiBundler.Call[]. That will
    ///                     reenter the bundler for the inner set of calls, prior to transferring
    ///                     collateral tokens to Morpho and checking LTV. Use empty bytes for no callback
    function supplyCollateral(uint256 amount, uint256 minAmount, bytes memory callbackData)
        external
        returns (uint256 supplied);

    /// @notice Withdraws collateral.
    /// @dev Will revert if
    ///       - `amount` is greater than the available collateral (unless set to `type(uint256).max`)
    ///       - If the LTV is above the liquidation LTV (It is allowed to be greater than the 'max safe LTV')
    /// @param amount The amount of collateral to withdraw. Pass `type(uint).max` to withdraw the adapter's
    ///               entire collateral balance.
    /// @param recipient The address that will receive the collateral assets.
    function withdrawCollateral(uint256 amount, address recipient) external returns (uint256 withdrawn);

    /// @notice Borrows assets.
    /// @dev Either `assets` or `shares` should be zero. Most use cases should rely on `assets` as an input so its
    /// guaranteed to borrow `assets` tokens, but the possibility to mint a specific amount of shares is
    /// given for full compatibility and precision.
    /// @dev Will revert if
    ///       - There isn't sufficient liquidity
    ///       - If the LTV is above the liquidation LTV (It is allowed to be greater than the 'max safe LTV')
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to mint.
    /// @param recipient The address that will receive the borrowed assets.
    function borrow(uint256 assets, uint256 shares, address recipient)
        external
        returns (uint256 borrowedAssets, uint256 borrowedShares);

    /// @notice Repays assets.
    /// @dev Either `assets` or `shares` should be zero. Most use cases should rely on `assets` as an input so the
    /// adapter is guaranteed to have `assets` tokens pulled from its balance, but the possibility to burn a specific
    /// amount of shares is given for full compatibility and precision.
    /// @dev Will revert if:
    ///       - Both `assets` and `shares` are specified
    ///       - There aren't enough loanTokens in this contract
    /// @param assets The amount of assets to repay. Pass `type(uint).max` to repay the adapter's loan asset balance.
    ///               Capped to the outstanding debt balance.
    /// @param minAssets When using `assets`, skip repaying debt if the derived assets amount is less than this
    /// threshold. This is useful to avoid wasting gas for dust. Not validated when using `shares` rather than `assets`
    /// @param shares The amount of shares to burn. Pass `type(uint).max` to repay the adapters's entire debt
    ///               But will revert if the required loanToken balance isn't available in the adapter contract.
    /// @param callbackData Arbitrary data to pass to the `onMorphoRepay` callback. Pass empty callbackData if not
    /// needed.
    function repay(uint256 assets, uint256 minAssets, uint256 shares, bytes calldata callbackData)
        external
        returns (uint256 repaidAssets, uint256 repaidShares);

    /****** BUNDLER PLUGIN CHECKS ******/

    /// @notice Validate that the LTV of this contract is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `LtvOutOfRange`
    function validateLtvInRange(uint256 minLtv, uint256 maxLtv) external view;

    /// @notice Validate that the Utilization Ratio of the `loanToken` within Morpho is
    /// is within an expected range
    /// @dev If in within range, this is a no-op. If out of range will revert with `UtilizationRatioOutOfRange`
    function validateLoanUtilizationRatioInRange(uint256 minUR, uint256 maxUR) external view;

    /****** VIEWS ******/

    /// @notice The maximum Utilization Ratio of the loan token allowed when
    /// joining into the vault. Specified in WAD.
    function maxLoanUtilizationRatioOnJoin() external view returns (uint256);

    /// @notice Encode the immutable args for cloning
    function encodeImmutableArgs(address _morpho, MorphoMarketParams memory _morphoMarketParams)
        external
        view
        returns (bytes memory);

    /// @notice Encode the initialization args
    function encodeInitArgs(address _initialOwner, uint256 _maxSafeLtv, uint256 _maxLoanUtilizationRatioOnJoin)
        external
        view
        returns (bytes memory);

    /// @notice The current `loanToken` utilization ratio on Morpho
    function currentLoanTokenUtilizationRatio() external view returns (uint256 utilizationRatio);

    /// @notice The Morpho market parameters
    function getMarketParams() external view returns (MorphoMarketParams memory);

    struct MorphoPositionDetails {
        /// @notice The amount of collateral supplied in the collateral units
        uint256 collateralSupplied;

        /// @notice Value of collateral converted into the liability units
        uint256 collateralValueInLiabilityTerms;

        /// @notice Value of liability
        uint256 liabilityValue;

        /// @notice The Loan-To-Value (LTV) where the position may be liquidated,
        /// given this account's debt/collateral
        /// Represented in WAD
        uint256 liquidationLtv;

        /// @notice The maximum Loan-To-Value (LTV) that this adapter can safely borrow up to,
        /// given this account's collateral/debt
        /// Represented in WAD
        uint256 maxSafeLtv;

        /// @notice The current LTV of this account
        /// Represented in WAD
        uint256 currentLtv;

        /// @notice The estimated health factor of this account's position
        uint256 healthFactor;
    }

    /// @notice Returns the Morpho position details
    function positionDetails() external view returns (MorphoPositionDetails memory);

    /// @notice Metrics relevant the max collateral which can be withdrawn
    struct AssetWithdrawMetrics {
        /// @notice The global amount of collateral supplied in Morpho which hasn't already been borrowed
        uint256 availableSupply;
    }

    /// @notice Metrics relevant the max liability which can be borrowed
    struct LiabilityBorrowMetrics {
        /// @notice The amount of debt already borrowed - includes accrued
        uint256 alreadyBorrowed;

        /// @notice The total debt liquidity (already borrowed and still available),
        /// ignoring any caps
        uint256 totalSupply;

        /// @notice The Origami policy cap taking `maxLoanUtilizationRatioOnJoin` into account.
        /// If no cap (if maxLoanUtilizationRatioOnJoin is set to 1e18), this is type(uint256).max
        uint256 joinBorrowCap;
    }

    /// @notice Metrics relevant the max liability which can be repaid
    struct LiabilityRepayMetrics {
        /// @notice The global amount of total debt that for this market in Morpho
        uint256 totalDebt;
    }

    /// @notice Get the supply/borrow metrics relevant to join constraints
    function joinMetrics() external view returns (LiabilityBorrowMetrics memory borrowMetrics);

    /// @notice Get the withdraw/repay metrics relevant to exit constraints
    function exitMetrics()
        external
        view
        returns (AssetWithdrawMetrics memory withdrawMetrics, LiabilityRepayMetrics memory repayMetrics);
}
