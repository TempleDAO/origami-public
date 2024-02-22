pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lovToken/managers/OrigamiLovTokenErc4626Manager.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

/**
 * @title Origami lovToken Manager for ERC-4626
 * @notice A lovToken which has reserves as ERC-4626 tokens.
 * This will rebalance by borrowing funds from the Origami Lending Clerk, 
 * and swapping to the origami deposit tokens using a DEX Aggregator.
 * @dev `depositAsset` and `reserveToken` are required to be exactly 18 decimal places (if this changes, a new version will be created)
 * `debtAsset` can be any decimal places <= 18
 */
interface IOrigamiLovTokenErc4626Manager is IOrigamiLovTokenManager, IOrigamiLendingBorrower {
    event RebalanceUp(
        uint256 depositAssetWithdrawn, 
        uint256 reserveAssetWithdrawn, 
        uint256 debtAmountToRepay,
        uint256 debtAmountRepaid,
        uint256 alRatioBefore, // The asset/liability ratio before the rebalance
        uint256 alRatioAfter, // The asset/liability ratio after the rebalance
        bool forceRebalance
    );
    event RebalanceDown(
        uint256 debtBorrowed,
        uint256 depositAssetReceived,
        uint256 reservesReceived,
        uint256 alRatioBefore, // The asset/liability ratio before the rebalance
        uint256 alRatioAfter, // The asset/liability ratio after the rebalance
        bool forceRebalance
    );

    event SwapperSet(address indexed swapper);
    event LendingClerkSet(address indexed lendingClerk);
    event OracleSet(address indexed oracle);

    /**
     * @notice Set the clerk responsible for managing borrows, repays and debt of borrowers
     */
    function setLendingClerk(address _lendingClerk) external;

    /**
     * @notice Set the swapper responsible for `depositAsset` <--> `debtAsset` swaps
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice Set the `depositAsset` <--> `debtAsset` oracle configuration 
     */
    function setOracle(address _oracle) external;

    struct RebalanceUpParams {
        // The amount of `depositAsset` to withdraw from reserves
        uint256 depositAssetsToWithdraw;

        // The min amount of `reserveToken` ERC-4626 shares expected to be removed when withdrawing from reserves
        uint256 minReserveAssetShares;

        // The swap quote data to swap from `depositAsset` -> `debtAsset`
        bytes swapData;

        // The minimum amount of `debtAsset` expected to be repaid -- how much we expect from the `depositAsset` -> `debtAsset` swap
        uint256 minDebtAmountToRepay;

        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The minimum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Increase the A/L by reducing liabilities. Exit some of the reserves and repay the debt
     */
    function rebalanceUp(RebalanceUpParams calldata params) external returns (uint128 alRatioAfter);

    /**
     * @notice Force a rebalanceUp ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceUp(RebalanceUpParams calldata params) external returns (uint128 alRatioAfter);

    struct RebalanceDownParams {
        // The amount of new `debtAsset` to borrow
        uint256 borrowAmount;

        // The swap quote data to swap from `debtAsset` -> `depositAsset`
        bytes swapData;

        // The minimum amount of ERC-4626 `reserveAsset` shares expected when depositing `depositAsset`
        uint256 minReservesOut;

        // The minimum acceptable A/L, will revert if below this
        uint128 minNewAL;

        // The minimum acceptable A/L, will revert if above this
        uint128 maxNewAL;
    }

    /**
     * @notice Decrease the A/L by increasing liabilities. Borrow new `debtAsset` and deposit into the reserves
     */
    function rebalanceDown(RebalanceDownParams calldata params) external returns (uint128 alRatioAfter);

    /**
     * @notice Force a rebalanceDown ignoring A/L ceiling/floor
     * @dev Separate function to above to have stricter control on who can force
     */
    function forceRebalanceDown(RebalanceDownParams calldata params) external returns (uint128 alRatioAfter);

    /**
     * @notice The asset which users deposit/exit with into the lovToken
     */
    function depositAsset() external view returns (IERC20Metadata);

    /**
     * @notice The Origami Lending Clerk responsible for managing borrows, repays and debt of borrowers
     */
    function lendingClerk() external view returns (IOrigamiLendingClerk);

    /**
     * @notice The swapper for `debtAsset` <--> `depositAsset`
     */
    function swapper() external view returns (IOrigamiSwapper);

    /**
     * @notice The oracle to convert `debtAsset` <--> `depositAsset`
     */
    function debtAssetToDepositAssetOracle() external view returns (IOrigamiOracle);
}
