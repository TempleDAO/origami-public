pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/lending/IOrigamiLendingClerk.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";
import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";
import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";
import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";

/**
 * @title Origami Lending Clerk
 * @notice Manage the supply/withdraw | borrow/repay of a single asset
 * oToken will supply the asset, and whitelisted borrowers (eg lovToken's) can borrow
 * paying an interest rate.
 * Any unutilised capital is allocated into an 'idle strategy' for extra capital efficiency
 * @dev supports an asset with decimals <= 18 decimal places
 */
interface IOrigamiLendingClerk {
    event GlobalPausedSet(bool pauseBorrow, bool pauseRepay);
    event BorrowerPausedSet(address indexed borrower, bool pauseBorrow, bool pauseRepay);
    event SupplyManagerSet(address indexed supplyManager);
    event BorrowerAdded(address indexed borrower, address indexed interestRateModel, string name, string version);
    event BorrowerRemoved(address indexed borrower);
    event BorrowerShutdown(address indexed borrower, uint256 outstandingDebt);
    event DebtCeilingUpdated(address indexed borrower, uint256 oldDebtCeiling, uint256 newDebtCeiling);
    event InterestRateModelUpdated(address indexed borrower, address indexed interestRateModel);

    event Deposit(address indexed fromAccount, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);
    event Borrow(address indexed borrower, address indexed recipient, uint256 amount);
    event Repay(address indexed borrower, address indexed from, uint256 amount);

    error BorrowerNotEnabled();
    error BorrowPaused();
    error RepayPaused();
    error DebtCeilingBreached(uint256 available, uint256 borrowAmount);
    error AlreadyEnabled();
    error AboveMaxUtilisation(uint256 utilisationRatio);

    struct BorrowerConfig {
        /**
         * @notice Pause borrows
         */
        bool borrowPaused;

        /**
         * @notice Pause repayments
         */
        bool repayPaused;

        /**
         * @notice The interest rate model for this borrower
         */
        IInterestRateModel interestRateModel;

        /**
         * @notice The borrower can borrow up to this limit of accrued debt.
         * The `debtToken` is minted on any borrows 1:1 (which then accrues interest)
         * When a borrower repays, the `debtToken` is burned 1:1
         */
        uint256 debtCeiling;
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the supply manager who is allowed to deposit/withdraw `asset`
     */
    function setSupplyManager(address _supplyManager) external;

    /**
     * @notice Pause all borrower borrows and repayments
     */
    function setGlobalPaused(bool _pauseBorrow, bool _pauseRepay) external;

    /**
     * @notice Set whether borrows and repayments are paused for a given borrower.
     */
    function setBorrowerPaused(address borrower, bool pauseBorrow, bool pauseRepay) external;

    /**
     * @notice Set global interest rate model
     */
    function setGlobalInterestRateModel(address _globalInterestRateModel) external;

    /**
     * @notice Register a new borrower with a given debt ceiling
     * @param borrower The new borrower address to add
     * @param interestRateModel The address of the interest rate model to use for this borrower
     * @param debtCeiling The debt ceiling, to `PRECISION` decimal places
     */
    function addBorrower(
        address borrower, 
        address interestRateModel,
        uint256 debtCeiling
    ) external;

    /**
     * @notice Update the debt ceiling for a given borrower
     * @param borrower The borrower address to update
     * @param newDebtCeiling The debt ceiling, to `PRECISION` decimal places
     */
    function setBorrowerDebtCeiling(address borrower, uint256 newDebtCeiling) external;

    /**
     * @notice Update the interest rate model for a given borrower
     * @param borrower The borrower address to update
     * @param interestRateModel The address of the interest rate model to use for this borrower
     */
    function setBorrowerInterestRateModel(address borrower, address interestRateModel) external;

    /**
     * @notice The idle strategy manager rate is updated periodically by the protocol
     * The yield from underlying strategies is dynamic, and so the rate will be updated periodically
     * (eg weekly) in order to roughly target a net equity of 0 for the idle strategy manager
     * @param rate The new interest rate to `PRECISION` decimal places
     */
    function setIdleStrategyInterestRate(uint96 rate) external;

    /**
     * @notice Shutdown a borrower. All available assets should be repaid by the borrower prior to calling.
     * Any outstanding debt is burned, but emitted as a `BorrowerShutdown` event.
     */
    function shutdownBorrower(address borrower) external;

    /**
     * @notice Refresh the interest rate for a set of borrowers, using the latest utilisation rates.
     */
    function refreshBorrowersInterestRate(address[] calldata borrowerList) external;

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The supply manager deposits `asset`, which
     * allocates the funds to the idle strategy and mints `debtToken`
     * @param amount The amount to deposit in `asset` decimal places, eg 6dp for USDC
     */
    function deposit(uint256 amount) external;

    /**
     * @notice The supply manager withdraws asset, which pulls the `asset` from 
     * the idle strategy and burns the `debtToken`
     * @dev Cannot pull more than the global amount available left to borrow
     * @param amount The amount to withdraw in `asset` decimal places, eg 6dp for USDC
     * @param recipient The receiver of the `asset` withdraw
     */
    function withdraw(uint256 amount, address recipient) external;

    /*//////////////////////////////////////////////////////////////
                             BORROW/REPAY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice An approved borrower calls to request more funding.
     * @dev This will revert if the borrower requests more stables than it's able to borrow.
     * `debtToken` will be minted 1:1 for the amount of asset borrowed
     * @param amount The amount to borrow in `asset` decimal places, eg 6dp for USDC
     * @param recipient The receiving address of the `asset` tokens
     */
    function borrow(uint256 amount, address recipient) external;

    /**
     * @notice A an approved borrower calls to request the most funding it can.
     * `debtToken` will be minted 1:1 for the amount of asset borrowed
     * @param recipient The receiving address of the `asset` tokens
     */
    function borrowMax(address recipient) external returns (uint256 borrowedAmount);

    /**
     * @notice Paydown debt for a borrower. This will pull the asset from the sender, 
     * and will burn the equivalent amount of debtToken from the borrower.
     * @dev The amount actually repaid is capped to the oustanding debt balance such
     * that it's not possible to overpay. Therefore this function can also be used to repay the entire debt.
     * @param amount The amount to repay in `asset` decimal places, eg 6dp for USDC
     * @param borrower The borrower to repay on behalf of
     */
    function repay(uint256 amount, address borrower) external returns (uint256 amountRepaid);

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS - GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The collateral asset that is supplied & borrowed
     */
    function asset() external view returns (IERC20Metadata);

    /**
     * @notice The Origami oToken which supplies the asset
     */
    function oToken() external view returns (IOrigamiOToken);

    /**
     * @notice Where idle funds (not yet borrowed) are deposited.
     */
    function idleStrategyManager() external view returns (IOrigamiIdleStrategyManager);

    /**
     * @notice The token issued to borrowers or idle strategy for the use of 
     * the collateral
     */
    function debtToken() external view returns (IOrigamiDebtToken);

    /**
     * @notice A circuit breaker is used to ensure no more than a capped amount
     * is borrowed in a given period
     */
    function circuitBreakerProxy() external view returns (IOrigamiCircuitBreakerProxy);

    /**
     * @notice The supply manager which is allowed to deposit/withdraw `asset`
     */
    function supplyManager() external view returns (address);

    /**
     * @notice True if borrows are paused for all borrowers.
     */
    function globalBorrowPaused() external view returns (bool);

    /**
     * @notice True if repayments are paused for all borrowers.
     */
    function globalRepayPaused() external view returns (bool);

    /**
     * @notice The configuration for a given borrower
     */
    function borrowers(address borrower) external view returns (
        bool borrowPaused,
        bool repayPaused,
        IInterestRateModel interestRateModel,
        uint256 debtCeiling
    );

    /**
     * @notice The global interest rate model
     */
    function globalInterestRateModel() external returns (IInterestRateModel);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The list of all borrowers currently added to the lending manager
     */
    function borrowersList() external view returns (address[] memory);

    struct BorrowerDetails {
        string name;
        string version;
        bool borrowPaused;
        bool repayPaused;
        address interestRateModel;
        uint256 debtCeiling;
    }

    /**
     * @notice A helper to collate information about a given borrower for reporting purposes.
     */
    function borrowerDetails(address borrower) external view returns (BorrowerDetails memory details);

    /**
     * @notice A borrower's current assets and liabilities
     * @dev Each asset is represented in it's natural decimals, the debt
     * is in `PRECISION` decimals
     */
    function borrowerBalanceSheet(address borrower) external view returns (
        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances,
        uint256 debtTokenBalance
    );

    /**
     * @notice A borrower's current debt as of now
     * @dev Represented as `PRECISION` decimals
     */
    function borrowerDebt(address borrower) external view returns (uint256);

    /**
     * @notice The current max debt ceiling that a borrower is allowed to borrow up to.
     * @dev Represented as `PRECISION` decimals
     */
    function borrowerDebtCeiling(address borrower) external view returns (uint256);

    /**
     * @notice The total available balance of `asset` available to be withdrawn or borrowed
     * @dev The minimum of:
     *    - The `asset` available in the idle strategy manager, and 
     *    - The available global capacity remaining
     * Represented in the underlying asset's decimals (eg 6dp for USDC)
     */
    function totalAvailableToWithdraw() external view returns (uint256);

    /**
     * @notice Calculate the amount remaining that can be borrowed for a particular borrower.
     * The min of the global available capacity and the remaining capacity given that borrower's
     * existing debt and configured ceiling.
     * @dev Represented in the underlying asset's decimals (eg 6dp for USDC)
     */

    function availableToBorrow(address borrower) external view returns (uint256);

    /**
     * @notice Calculate the net interest rate for a given borrower
     * The maximum of the 'global' interest rate and this borrowers specific interest rate
     * @dev It is possible for this to be >100% as debt grows over time
     * 100% == 1e18
     */
    function calculateCombinedInterestRate(address borrower) external view returns (uint96);

    /**
     * @notice Calculate the global interest rate, based off the current global utilisation ratio
     * @dev It is possible for this to be >100% as debt grows over time
     * 100% == 1e18
     */
    function calculateGlobalInterestRate() external view returns (uint96);

    /**
     * @notice The global utilisation ratio across all borrowers
     * global UR = total borrower debt / oToken circulating supply
     * This will:
     *   - Increase when the debt increases (new borrow or interest), decrease on debt repayments (numerator)
     *   - Increase on user exits, decrease on user deposits or when new oToken is minted as new reserves
     *     for newly accrued iUSDC (denominator)
     * 100% == 1e18
     */
    function globalUtilisationRatio() external view returns (uint256);

    /**
     * @notice The total debt across all borrowers (excluding the idle strategy manager)
     * @dev Accrued debt data may be slightly stale for each borrower & idle strategy
     * So periodic checkpoints are required.
     * @dev Represented as `PRECISION` decimals
     */
    function totalBorrowerDebt() external view returns (uint256);

    /**
     * @notice Calculate the latest borrower specific interest rate, using the latest utilisation
     * ratio of that borrower
     * @dev Represented in `PRECISION` decimal places
     */
    function calculateBorrowerInterestRate(address borrower) external view returns (uint96);

    /**
     * @notice The utilisation ratio for a given borrower
     * borrower specific UR = debt balance / debt ceiling
     * Represented in `PRECISION` decimal places
     */
    function borrowerUtilisationRatio(address borrower) external view returns (uint256);
}
