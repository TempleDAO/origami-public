pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/olympus/IOrigamiHOhmManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IMonoCooler } from "contracts/interfaces/external/olympus/IMonoCooler.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

/**
 * @title Origami lovOHM Manager
 * @notice Handles adding and removing collateral and max borrowing in Olympus' MonoCooler
 *
 * @dev
 *   - There will be a surplus `debtToken` amount held by this contract which can expand and contract
 *     on each join and exit. 
 *   - This surplus is excluded from the balance sheet totals used to calculate the `debtToken per hOHM` 
 *     share price.
 *   - Under normal circumstances it will grow on aggregate:
 *     a/ The origination LTV within cooler increases every second to some set gradient. 
 *        This increases the capacity to borrow
 *     b/ The cooler interest rate is flat (0.5% APY as of writing). 
 *        This decreases the capacity to borrow
 *     c/ Any surplus is added into a savings vault (eg sUSDS) which has a higher interest rate than (b). 
 *        The surplus in debtToken terms (eg USDS) increases faster than the cooler debt.
 *     It is expected that (a)+(c) will outpace (b)
 *   - sweep() can be called in order to use the surplus `debtToken` to buy hOHM from the open market
 *     and then burn the hOHM. 
 *     When this happens the totalSupply decreases, which increases the share price of both the collateral and 
 *     debt tokens per hOHM
 */
interface IOrigamiHOhmManager is IOrigamiSwapCallback, IERC165 {
    event CoolerBorrowsDisabledSet(bool value);
    event SwapperSet(address indexed newSwapper);
    event SweepParamsSet(uint40 newSweepCooldownSecs, uint96 newMaxSweepSellAmount);
    event DebtTokenSet(address indexed debtToken, address indexed savingsVault);
    event PerformanceFeeSet(uint256 fee);
    event FeeCollectorSet(address indexed feeCollector);
    event ExitFeeBpsSet(uint256 feeBps);

    /// @notice The swap was initiated to sell `debtTokenAmount` of surplus debtTokens into hOHM
    event SweepStarted(address indexed debtToken, uint256 debtTokenAmount);

    /// @notice The swap was finalized. An amount was burned, and an amount was sent to the `feeCollector`
    /// @dev The SweepStarted and SweepFinished events may be executed across multiple transactions.
    event SweepFinished(uint256 hohmBurned, uint256 feeAmount);

    /// @notice A join has been performed by adding the `collateralAmount` as collateral into cooler
    /// and paying `receiver` the `debtAmount` of debtToken's. 
    /// `collateralAmount` and `debtAmount` are always in the tokens native decimals.
    /// `coolerDebtDeltaInWad` is how much debt was borrowed (positive value) or repaid (negative value) in
    ///  cooler in order to get to the max origination LTV (always to 18 decimals regardless of the debt token)
    event Join(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    /// @notice An exit has been performed by repaying debt and withdrawing the `collateralAmount` from cooler
    /// and sending to the `receiver`
    /// `collateralAmount` and `debtAmount` are always in the tokens native decimals.
    /// `coolerDebtDeltaInWad` is how much debt was borrowed (positive value) or repaid (negative value) in
    ///  cooler in order to get to the max origination LTV (always to 18 decimals regardless of the debt token)
    event Exit(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    error IsNotPaused();
    error BeforeCooldownEnd();
    error SweepTooLarge();

    /**
     * @notice Set the exit fees which are taken in kind. This benefits existing
     * vault owners, they do not go to Origami Treasury.
     * @dev Fees cannot increase
     * Represented in basis points
     */
    function setExitFees(uint16 newFeeBps) external;

    /**
     * @notice Set whether cooler borrows are currently disabled
     */
    function setCoolerBorrowsDisabled(bool value) external;

    /**
     * @notice Set the sweep cooldown seconds and max debt token sell amount
     * for each call
     */
    function setSweepParams(
        uint40 newSweepCooldownSecs,
        uint96 newMaxSweepSellAmount
    ) external;

    /**
     * @notice Set the swapper contract responsible for swapping 
     * `debtToken` to lovOHM
     */
    function setSweepSwapper(address newSwapper) external;

    /**
     * @notice Set the performance fees for Origami
     * Represented in basis points
     */
    function setPerformanceFeesBps(uint16 newFeeBps) external;

    /**
     * @notice Set the Origami performance fee collector address
     */
    function setFeeCollector(address newFeeCollector) external;

    /**
     * @notice If the Olympus Cooler debtToken has changed (eg USDS => USDC), then this will
     * need to be called. 
     * @dev Full fork testing is expected to be done first given it is a somewhat manual process.
     *  - The vault is required to be paused first
     *  - Any surplus 'old' debt token will need to be sold into the 'new' debt token
     *    The old debt token & savings vault token can be recovered in order to do this, 
     *    once this function has been called.
     *  - `setSweepParams()` will need to be called especially if the new debt token has 
     *    different decimal places
     *  - Once set, the hOHM vault will need to have `setManager()` called to refresh it's
     *    cached debtToken value
     *  - Only once all updated should the vault be unpaused.
     * @param savingsVault The debtToken can optionally be deposited IOrigamiHOhmManagerinto an ERC4626 vault (eg sUSDS)
     *                     in order to have passive yield. If not required, can be set to address(0)
     */
    function setDebtTokenFromCooler(address savingsVault) external;
    
    /**
     * @notice Deposit/Withdraw from the savings vault such that the debt token amount in this contract
     * is a certain balance.
     * @dev The amount actually withdrawn from savings will be capped to the max amount possible.
     * `requiredDebtTokenBalance` is expected to be in the decimal places of `debtToken`
     */
    function syncDebtTokenSavings(uint256 requiredDebtTokenBalance) external;

    /**
     * @notice Sweeping will sell a number of surplus debtToken's for the hOHM vault token
     *   and then burns the resulting hOHM vault token.
     * @dev 
     *   - When the hOHM tokens are burned, the share price of both the collateral and debt tokens
     *     will increase.
     *   - sweep's are limited in the amount per call and also how frequently it can be called
     *   - swapData is the encoded bytes of the swapper (if required for that implementation). It's
     *     up to the swapper to perform slippage checks and also to burn the purchased hOHM
     * `amount` is expected to be in the decimal places of `debtToken`
     */
    function sweep(
        uint256 amount,
        bytes memory swapData
    ) external;

    /**
     * @notice Add equity by depositing `collateralAmount` collateral and borrowing `debtAmount` from Cooler.
     * Receiver receives the `debtAmount`
     * @param collateralAmount The amount of collateral to deposit, in its native decimals places
     * @param debtAmount the amount of debt to send to the receiver, in its native decimals places
     * @param receiver The address to receive the `debtAmount` of `debtToken`
     * @param receiverSharesPostMint The number of shares `receiver` will have including after the effect of
              this vault join
     * @param totalSupplyPostMint The vault total supply including after this vault join
     */
    function join(   
        uint256 collateralAmount,
        uint256 debtAmount,
        address receiver,
        uint256 receiverSharesPostMint,
        uint256 totalSupplyPostMint
    ) external;

    /**
     * @notice Remove equity by repaying `debtAmount` and removing `collateralAmount` collateral from Cooler.
     * Receiver receives the gOHM collateral
     * @param collateralAmount The amount of collateral to send to the receiver, in its native decimals places
     * @param debtAmount the amount of debt to repay, in its native decimals places
     * @param sharesOwner the owner of the shares who is exiting
     * @param receiver The address to receive the `collateralAmount` of `collateralToken`
     * @param ownerSharesPostBurn The number of shares `sharesOwner` will have including after the effect of
              this vault exit
     * @param totalSupplyPostBurn The vault total supply including after this vault exit
     */
    function exit(
        uint256 collateralAmount,
        uint256 debtAmount,
        address sharesOwner,
        address receiver,
        uint256 ownerSharesPostBurn,
        uint256 totalSupplyPostBurn
    ) external;

    /**
     * @notice Update the gOHM delegate address and amount for a particular account.
     * The new gOHM amount is based on the latest gOHM collateral this contract has in cooler 
     * and the accounts share proportion of the totalSupply.
     * @dev 
     *  - `account` cannot be address(0) - this will revert
     *  - `newDelegateAddress` may be address(0), meaning that gOHM collateral will become
     *    undelegated.
     *  - `newDelegateAddress` may remain the same as the existing one, meaning just the amount
     *    is updated
     *  - `accountShares` may be zero, meaning that any existing gOHM collateral is undelegated.
     *    Future calls to `updateAmounts()` for this account will still delegate to `newDelegateAddress`
     */
    function updateDelegateAndAmount(
        address account, 
        uint256 accountShares, 
        uint256 totalSupply, 
        address newDelegateAddress
    ) external;

    /**
     * @notice Update the gOHM delegation amount for one account, using the 
     * existing delegate address (if set).
     * The new gOHM amount is based on the latest gOHM collateral this contract has in cooler 
     * and the accounts share proportion of the totalSupply.
     * @dev 
     *  - `account` cannot be address(0) - this will revert
     *  - The existing delegate address for the account may be address(0) in which case
     *    no change is made - the gOHM remains undelegated
     *  - `accountShares` may be zero, meaning that any existing gOHM collateral is undelegated.
     *    Future calls to `setDelegationAmount1()` or `setDelegationAmount2()` for this account 
     *    will still delegate to their existing delegate
     */
    function setDelegationAmount1(
        address account,
        uint256 accountShares,
        uint256 totalSupply
    ) external;

    /**
     * @notice Update the gOHM delegation amounts for two accounts, using the 
     * existing delegate address for that account (if set).
     * The new gOHM amount for that account is based on the latest gOHM collateral this contract has in cooler 
     * and the accounts share proportion of the totalSupply.
     * @dev 
     *  - `account1` cannot be the same as `account2` - this will revert.
     *  - `account1` or `account2` cannot be address(0) - this will revert.
     *  - The existing delegate address for the account may be address(0) in which case
     *    no change is made - the gOHM remains undelegated
     *  - `accountShares1` or `accountShares2` may be zero, meaning that any existing gOHM collateral is undelegated.
     *    Future calls to `setDelegationAmount1()` or `setDelegationAmount2()` for that account 
     *    will still delegate to their existing delegate
     */
    function setDelegationAmount2(
        address account1,
        uint256 account1Shares,
        address account2,
        uint256 account2Shares,
        uint256 totalSupply
    ) external;

    /**
     * @notice Synchronise the the LTV such that it equals (or is just under) the max origination LTV in cooler
     * @dev Provided in case there have been no new joins/exits for some time (which auto max-borrow)
     *   - If the current LTV is greater than the cooler origination LTV, this will repay (using surplus debtToken)
     *   - If the current LTV is less than the cooler origination LTV, this will borrow (increasing the surplus)
     * Will revert if `coolerBorrowsDisabled` is true and a cooler borrow is attempted.
     * A positive `coolerDebtDeltaInWad` means that amount has been borrowed and added to surplus
     * A negative `coolerDebtDeltaInWad` means that amount has been repaid from the surplus
     */
    function maxBorrowFromCooler() external returns (int128 coolerDebtDeltaInWad);

    /**
     * @notice The Origami vault this is managing
     */
    function vault() external view returns (address);

    /**
     * @notice Whether joinWithShares and joinWithAssets are currently paused
     */
    function areJoinsPaused() external view returns (bool);

    /**
     * @notice Whether exitToShares and exitToAssets are currently paused
     */
    function areExitsPaused() external view returns (bool);

    /**
     * @notice The Olympus Cooler contract.
     */
    function cooler() external view returns (IMonoCooler);

    /**
     * @notice The Olympus Governance token (gOHM)
     */
    function collateralToken() external view returns (IERC20);

    /**
     * @notice The current debt token (eg USDS)
     * @dev must have decimal places <= 18
     */
    function debtToken() external view returns (IERC20);

    /**
     * @notice The multiplier to convert `debtToken` into WAD
     */
    function debtTokenDecimalsToWadScalar() external view returns (uint96);

    /**
     * @notice A ERC4626 vault for `debtToken` savings.
     */
    function debtTokenSavingsVault() external view returns (IERC4626);

    /**
     * @notice The amount of shares which are burned prior to redeeming for underlying assets.
     * This benefits existing vault owners, they do not go to Origami Treasury.
     * @dev Fees cannot increase
     * Represented in basis points
     */
    function exitFeeBps() external view returns (uint16 feeBps);

    /**
     * @notice Cooler borrows may need to be disabled in order to allow
     * exits (and cooler repayments)
     */
    function coolerBorrowsDisabled() external view returns (bool);

    /**
     * @notice Set the swapper contract responsible for swapping 
     * `debtToken` to lovOHM
     */
    function sweepSwapper() external view returns (IOrigamiSwapper);

    /**
     * @notice Sweeping can only be performed once every `sweepCooldownSecs`
     */
    function sweepCooldownSecs() external view returns (uint40);

    /**
     * @notice The last time sweep was successfully called
     */
    function lastSweepTime() external view returns (uint40);

    /**
     * @notice The maximum amount of debtToken which can be sold in each sweep
     * In the decimal places of `debtToken`
     */
    function maxSweepSellAmount() external view returns (uint96);

    /**
     * @notice The address used to collect the Origami performance fees
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The performance fee to Origami treasury
     * Represented in basis points
     */
    function performanceFeeBps() external view returns (uint16);

    /**
     * @notice The maximum exit fee in basis points: 3.3%
     */
    function MAX_EXIT_FEE_BPS() external view returns (uint16 feeBps);

    /**
     * @notice The maximum performance fee that Origami can take when calling sweep()
     */
    function MAX_PERFORMANCE_FEE_BPS() external view returns (uint16);

    /**
     * @notice The minimum amount of gOHM collateral required in order to delegate
     * @dev 
     *    - If the account's proportional gOHM falls below this on a transfer/exit then 
     *      the delegation will be rescinded in Cooler
     *    - If the account sets a delegation and the gOHM collateral is less than this threshold
     *      the delegation won't apply
     *    - If the account has set a delegation and then the gOHm collateral balance increases over
     *      the threshold, the delegation will be applied on the next sync
     */
    function MIN_DELEGATION_AMOUNT() external view returns (uint256);

    /**
     * @notice The current delegate address and gOHM collateral 
     * amount delegated for an account
     */
    function delegations(address account) external view returns (address delegateAddress, uint256 amount);

    /**
     * @notice The net balance of `debtToken` used for the `debtToken per hOHM` share price
     * @dev Defined as the current cooler debt minus any surplus debtToken held for future buybacks
     * In the decimal places of `debtToken`
     */
    function debtTokenBalance() external view returns (uint256);

    /**
     * @notice The net balance of `collateralToken` used for the `collateralToken per hOHM` share price
     * In the decimal places of `collateralToken`
     */
    function collateralTokenBalance() external view returns (uint256);

    /**
     * @notice Convert a number of shares to the proportional amount of gOHM collateral tokens
     * @dev Will revert if `shares` is greater than `totalSupply`
     * shares, totalSupply and collateral are in 18 decimal places
     */
    function convertSharesToCollateral(uint256 shares, uint256 totalSupply) external view returns (uint256);

    /**
     * @notice Given an account and their shares, calculate the proportional amount of gOHM collateral
     * that account is eligable to delegate, and their current delegate and delegated amount
     */
    function accountDelegationBalances(
        address account,
        uint256 shares,
        uint256 totalSupply
    ) external view returns (
        uint256 totalCollateral,
        address delegateAddress,
        uint256 delegatedCollateral
    );

    /**
     * @notice The surplus amount of surplusDebtTokenAmount (in `debtToken` liability terms)
     * @dev This includes:
     *   - debtToken held in this contract
     *   - debtTokenSavingsVault (in debtToken terms) held in this contract
     *   - debtToken held in this the `sweepSwapper` (waiting to be swapped)
     * In the decimal places of `debtToken`
     */
    function surplusDebtTokenAmount() external view returns (uint256);

    /**
     * @notice The current balance of debt (including interest) in OHM Cooler (in `debtToken` liability terms)
     * @dev To 18 decimal places (WAD) regardless of the debt token
     */
    function coolerDebtInWad() external view returns (uint128);
}
