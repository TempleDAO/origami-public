pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/lending/OrigamiLendingClerk.sol)

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";
import { IInterestRateModel } from "contracts/interfaces/common/interestRate/IInterestRateModel.sol";
import { IOrigamiOToken } from "contracts/interfaces/investments/IOrigamiOToken.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { IOrigamiIdleStrategyManager } from "contracts/interfaces/investments/lending/idleStrategy/IOrigamiIdleStrategyManager.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/**
 * @title Origami Lending Clerk
 * @notice Manage the supply/withdraw | borrow/repay of a single asset
 * oToken will supply the asset, and whitelisted borrowers (eg lovToken's) can borrow
 * paying an interest rate.
 * Any unutilised capital is allocated into an 'idle strategy' for extra capital efficiency
 * @dev supports an asset with decimals <= 18 decimal places
 */
contract OrigamiLendingClerk is IOrigamiLendingClerk, OrigamiElevatedAccess {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IOrigamiDebtToken;
    using EnumerableSet for EnumerableSet.AddressSet;
    using OrigamiMath for uint256;

    /**
     * @notice The collateral asset that is supplied & borrowed
     */
    IERC20Metadata public immutable override asset;

    /**
     * @notice The Origami oToken which supplies the asset
     */
    IOrigamiOToken public immutable override oToken;

    /**
     * @notice Where idle funds (not yet borrowed) are deposited.
     */
    IOrigamiIdleStrategyManager public immutable override idleStrategyManager;

    /**
     * @notice The token issued to borrowers or idle strategy for the use of 
     * the collateral
     */
    IOrigamiDebtToken public immutable override debtToken;

    /**
     * @notice A circuit breaker is used to ensure no more than a capped amount
     * is borrowed in a given period
     */
    IOrigamiCircuitBreakerProxy public immutable override circuitBreakerProxy;

    /**
     * @notice The scalar to convert asset to `PRECISION` decimals (used for both the `oToken` and `debtToken`)
     */
    uint256 private immutable _assetScalar;

    /**
     * @notice The supply manager which is allowed to deposit/withdraw `asset`
     */
    address public override supplyManager;

    /**
     * @notice True if borrows are paused for all borrowers.
     */
    bool public override globalBorrowPaused;

    /**
     * @notice True if repayments are paused for all borrowers.
     */
    bool public override globalRepayPaused;

    /**
     * @notice The configuration for a given borrower
     */
    mapping(address borrower => BorrowerConfig config) public override borrowers;

    /**
     * @notice The list of all borrowers currently added to the lending manager
     */
    EnumerableSet.AddressSet private _borrowersSet;

    /**
     * @notice The global interest rate model
     */
    IInterestRateModel public override globalInterestRateModel;

    /**
     * @notice The internal precision used for UR, IR, debt token precision, etc
     */
    uint256 internal constant PRECISION = 1e18;

    constructor(
        address _initialOwner,
        address _asset,
        address _oToken,
        address _idleStrategyManager,
        address _debtToken,
        address _circuitBreakerProxy,
        address _supplyManager,
        address _globalInterestRateModel
    ) OrigamiElevatedAccess(_initialOwner) {
        asset = IERC20Metadata(_asset);
        oToken = IOrigamiOToken(_oToken);
        idleStrategyManager = IOrigamiIdleStrategyManager(_idleStrategyManager);
        debtToken = IOrigamiDebtToken(_debtToken);
        circuitBreakerProxy = IOrigamiCircuitBreakerProxy(_circuitBreakerProxy);

        // Set the asset scalar to convert from asset <--> oToken or debToken
        // The asset cannot have more than 18 decimal places
        {
            uint8 _assetDecimals = asset.decimals();
            uint8 _origamiDecimals = oToken.decimals();
            if (debtToken.decimals() != _origamiDecimals) revert CommonEventsAndErrors.InvalidToken(_debtToken);
            if (_assetDecimals > _origamiDecimals) revert CommonEventsAndErrors.InvalidToken(_asset);
            _assetScalar = 10 ** (_origamiDecimals - _assetDecimals);
        }

        // Allow the idle strategy manager to always pull funds from the lending manager.
        asset.forceApprove(_idleStrategyManager, type(uint256).max);

        supplyManager = _supplyManager;
        globalInterestRateModel = IInterestRateModel(_globalInterestRateModel);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the supply manager who is allowed to deposit/withdraw `asset`
     */
    function setSupplyManager(address _supplyManager) external override onlyElevatedAccess {
        if (_supplyManager == address(0)) revert CommonEventsAndErrors.InvalidAddress(_supplyManager);
        emit SupplyManagerSet(_supplyManager);
        supplyManager = _supplyManager;
    }

    /**
     * @notice Pause all borrower borrows and repayments
     */
    function setGlobalPaused(bool _pauseBorrow, bool _pauseRepay) external override onlyElevatedAccess {
        emit GlobalPausedSet(_pauseBorrow, _pauseRepay);
        globalBorrowPaused = _pauseBorrow;
        globalRepayPaused = _pauseRepay;
    }

    /**
     * @notice Set whether borrows and repayments are paused for a given borrower.
     */
    function setBorrowerPaused(
        address borrower, 
        bool pauseBorrow, 
        bool pauseRepay
    ) external override onlyElevatedAccess {
        BorrowerConfig storage _borrowerConfig = _getBorrowerConfig(borrower);
        emit BorrowerPausedSet(borrower, pauseBorrow, pauseRepay);
        _borrowerConfig.borrowPaused = pauseBorrow;
        _borrowerConfig.repayPaused = pauseRepay;
    }

    /**
     * @notice Set global interest rate model
     */
    function setGlobalInterestRateModel(address _globalInterestRateModel) external override onlyElevatedAccess {
        if (_globalInterestRateModel == address(0)) revert CommonEventsAndErrors.InvalidAddress(_globalInterestRateModel);

        emit InterestRateModelUpdated(address(this), _globalInterestRateModel);
        globalInterestRateModel = IInterestRateModel(_globalInterestRateModel);
    }

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
    ) external override onlyElevatedAccess {
        if (borrower == address(0)) revert CommonEventsAndErrors.InvalidAddress(borrower);
        if (interestRateModel == address(0)) revert CommonEventsAndErrors.InvalidAddress(interestRateModel);
        if (!_borrowersSet.add(borrower)) revert AlreadyEnabled();

        IOrigamiLendingBorrower _borrower = IOrigamiLendingBorrower(borrower);
        emit BorrowerAdded(
            borrower, 
            interestRateModel, 
            _borrower.name(),
            _borrower.version()
        );
        BorrowerConfig storage borrowerConfig = borrowers[borrower];

        emit DebtCeilingUpdated(
            borrower, 
            borrowerConfig.debtCeiling, 
            debtCeiling
        );
        borrowerConfig.interestRateModel = IInterestRateModel(interestRateModel);
        borrowerConfig.debtCeiling = debtCeiling;
    }

    /**
     * @notice Update the debt ceiling for a given borrower
     * @param borrower The borrower address to update
     * @param newDebtCeiling The debt ceiling, to `PRECISION` decimal places
     */
    function setBorrowerDebtCeiling(address borrower, uint256 newDebtCeiling) external override onlyElevatedAccess {
        BorrowerConfig storage borrowerConfig = _getBorrowerConfig(borrower);
        emit DebtCeilingUpdated(borrower, borrowerConfig.debtCeiling, newDebtCeiling);
        borrowerConfig.debtCeiling = newDebtCeiling;

        // The debt token balances for both the idle strategy and borrower are checkpoint
        // to make the Global utilisation rate more accurate
        _checkpointDebtTokenBalances(borrower);
        _refreshBorrowersInterestRate(borrower, borrowerConfig, false);
    }

    /**
     * @notice Update the interest rate model for a given borrower
     * @param borrower The borrower address to update
     * @param interestRateModel The address of the interest rate model to use for this borrower
     */
    function setBorrowerInterestRateModel(
        address borrower, 
        address interestRateModel
    ) external override onlyElevatedAccess {
        if (interestRateModel == address(0)) revert CommonEventsAndErrors.InvalidAddress(interestRateModel);

        BorrowerConfig storage borrowerConfig = _getBorrowerConfig(borrower);
        emit InterestRateModelUpdated(borrower, interestRateModel);
        borrowerConfig.interestRateModel =  IInterestRateModel(interestRateModel);

        // The debt token balances for both the idle strategy and borrower are checkpoint
        // to make the Global utilisation rate more accurate
        _checkpointDebtTokenBalances(borrower);
        _refreshBorrowersInterestRate(borrower, borrowerConfig, false);
    }

    /**
     * @notice The idle strategy manager rate is updated periodically by the protocol
     * The yield from underlying strategies is dynamic, and so the rate will be updated periodically
     * (eg weekly) in order to roughly target a net equity of 0 for the idle strategy manager
     * @param rate The new interest rate to `PRECISION` decimal places. 1e18 represents 100% APY
     */
    function setIdleStrategyInterestRate(uint96 rate) external override onlyElevatedAccess {
        // Event emitted within the debtToken
        debtToken.setInterestRate(address(idleStrategyManager), rate);
    }

    /**
     * @notice Shutdown a borrower. All available assets should be repaid by the borrower prior to calling.
     * Any outstanding debt is burned, but emitted as a `BorrowerShutdown` event.
     */
    function shutdownBorrower(address borrower) external override onlyElevatedAccess {
        if (!_borrowersSet.remove(borrower)) revert BorrowerNotEnabled();
        delete borrowers[borrower];

        uint256 _outstandingDebt = debtToken.burnAll(borrower);
        emit BorrowerShutdown(borrower, _outstandingDebt);
    }

    /**
     * @notice Refresh the interest rate for a set of borrowers, using the latest utilisation rates.
     */
    function refreshBorrowersInterestRate(address[] calldata borrowerList) external override onlyElevatedAccess {
        uint256 _length = borrowerList.length;

        // First checkpoint the debtors interest for both the borrowerList and also
        // the idleStrategyManager
        // Although awkward in Solidity, it's more efficient duplicate the array and add the idleStrategyManager,
        // as opposed to calling debtToken.checkpointDebtorsInterest() an extra separate time.
        uint256 i = 1;
        {
            uint256 _debtTokenHoldersLength = _length + 1;
            address[] memory _debtTokenHolders = new address[](_debtTokenHoldersLength);
            _debtTokenHolders[0] = address(idleStrategyManager);
            for (; i < _debtTokenHoldersLength; ++i) {
                _debtTokenHolders[i] = borrowerList[i-1];
            }

            // Checkpoint the debtToken totals first
            debtToken.checkpointDebtorsInterest(_debtTokenHolders);
        }

        // Now refresh the interest rate for each of the borrowers
        {
            address _borrower;
            for (i=0; i < _length; ++i) {
                _borrower = borrowerList[i];
                _refreshBorrowersInterestRate(_borrower, _getBorrowerConfig(_borrower), false);
            }
        }
    }

    /**
     * @notice Recover any token -- this contract should not ordinarily hold any tokens.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20Metadata(token).safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The supply manager deposits `asset`, which
     * allocates the funds to the idle strategy and mints `debtToken`
     * @param amount The amount to deposit in `asset` decimal places, eg 6dp for USDC
     */
    function deposit(uint256 amount) external override onlySupplyManager {
        emit Deposit(msg.sender, amount);

        // Transfer the idle funds in and allocate into the idle strategy
        asset.safeTransferFrom(msg.sender, address(this), amount);
        idleStrategyManager.allocate(amount);

        // Issue new debt for the idle strategy manager.
        debtToken.mint(address(idleStrategyManager), amount.scaleUp(_assetScalar));
    }

    /**
     * @notice The supply manager withdraws asset, which pulls the `asset` from 
     * the idle strategy and burns the `debtToken`
     * @dev Cannot pull more than the global amount available left to borrow
     * @param amount The amount to withdraw in `asset` decimal places, eg 6dp for USDC
     * @param recipient The receiver of the `asset` withdraw
     */
    function withdraw(uint256 amount, address recipient) external override onlySupplyManager {
        emit Withdraw(recipient, amount);

        // Ensure that there is enough capacity to withdraw without bringing the global
        // UR > 100% as of the current checkpoint.
        // The total borrower debt may ever so slightly less than they could be because of accrued debt since the
        // last checkpoint of each borrower. So once all borrower debt is updated (done periodically), 
        // this may drag the UR slightly >100%. This behaviour is expected and ok.
        // Similarly new oToken's are minted periodically for any accrued debt, which would drag the UR
        // down again.
        uint256 _available = _globalAvailableToBorrow();
        if (amount > _available) revert CommonEventsAndErrors.InsufficientBalance(address(asset), amount, _available);

        // Burn the debt from the idleStrategyManager.
        debtToken.burn(address(idleStrategyManager), amount.scaleUp(_assetScalar));
        
        // Pull funds from idle strategy and send to recipient
        // If there aren't enough idle funds to cover this amount then it will revert.
        idleStrategyManager.withdraw(amount, recipient);
    }

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
    function borrow(uint256 amount, address recipient) external override {
        _borrow(msg.sender, recipient, _getBorrowerConfig(msg.sender), amount);
    }

    /**
     * @notice A an approved borrower calls to request the most funding it can.
     * `debtToken` will be minted 1:1 for the amount of asset borrowed
     * @param recipient The receiving address of the `asset` tokens
     */
    function borrowMax(address recipient) external override returns (uint256 borrowedAmount) {
        BorrowerConfig storage _borrowerConfig = _getBorrowerConfig(msg.sender);

        borrowedAmount = _availableToBorrow(msg.sender, _borrowerConfig);
        if (borrowedAmount != 0) {
            _borrow(msg.sender, recipient, _borrowerConfig, borrowedAmount);
        }
    }

    /**
     * @notice Paydown debt for a borrower. This will pull the asset from the sender, 
     * and will burn the equivalent amount of debtToken from the borrower.
     * @dev The amount actually repaid is capped to the oustanding debt balance such
     * that it's not possible to overpay. Therefore this function can also be used to repay the entire debt.
     * @param amount The amount to repay in `asset` decimal places, eg 6dp for USDC
     * @param borrower The borrower to repay on behalf of
     */
    function repay(uint256 amount, address borrower) external override returns (uint256 amountRepaid) {
        // Borrower can repay for themselves, Elevated Access can repay on behalf of others.
        if (msg.sender != borrower && !isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        
        BorrowerConfig storage _borrowerConfig = _getBorrowerConfig(borrower);

        // Get the borrower's current debt balance and convert to a max amount which can
        // be repaid
        // This scaleDown intentionally rounds UP to calculate the amount required from the user
        // So it's not in the borrower's benefit
        uint256 _debtBalance = debtToken.balanceOf(borrower);     // 18 dp
        uint256 _maxRepayAmount = _debtBalance.scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_UP);   // asset's dp

        // The repaid amount is then capped to _maxRepayAmount
        uint256 _debtToTransfer;  // 18 dp
        if (amount < _maxRepayAmount) {
            // If the amount is < the max repay, then calculate
            // how much debt to transfer by scaling up the asset amount
            amountRepaid = amount;
            _debtToTransfer = amount.scaleUp(_assetScalar);
        } else {
            // If the amount is >= the max repay, then use the outstanding
            // debt balance
            amountRepaid = _maxRepayAmount;
            _debtToTransfer = _debtBalance;
        }

        if (amountRepaid != 0) {
            _repay(msg.sender, borrower, _borrowerConfig, amountRepaid, _debtToTransfer);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The list of all borrowers currently added to the lending manager
     */
    function borrowersList() external override view returns (address[] memory) {
        return _borrowersSet.values();
    }

    /**
     * @notice A helper to collate information about a given borrower for reporting purposes.
     */
    function borrowerDetails(address borrower) external override view returns (
        BorrowerDetails memory details
    ) {
        BorrowerConfig storage borrowerConfig = _getBorrowerConfig(borrower);
        IOrigamiLendingBorrower _borrower = IOrigamiLendingBorrower(borrower);
        details = BorrowerDetails({
            name: _borrower.name(),
            version: _borrower.version(),
            borrowPaused: borrowerConfig.borrowPaused,
            repayPaused: borrowerConfig.repayPaused,
            interestRateModel: address(borrowerConfig.interestRateModel),
            debtCeiling: borrowerConfig.debtCeiling
        });
    }

    /**
     * @notice A borrower's current assets and liabilities
     * @dev Each asset is represented in it's natural decimals, the debt
     * is in `PRECISION` decimals
     */
    function borrowerBalanceSheet(address borrower) external override view returns (
        IOrigamiLendingBorrower.AssetBalance[] memory assetBalances,
        uint256 debtTokenBalance
    ) {
        if (borrower != address(idleStrategyManager)) {
            if (!_borrowersSet.contains(borrower)) {
                return (new IOrigamiLendingBorrower.AssetBalance[](0), 0);
            }
        }

        IOrigamiLendingBorrower _borrower = IOrigamiLendingBorrower(borrower);
        assetBalances = _borrower.latestAssetBalances();
        debtTokenBalance = debtToken.balanceOf(borrower);
    }

    /**
     * @notice A borrower's current debt as of now
     * @dev Represented as `PRECISION` decimals
     */
    function borrowerDebt(address borrower) external override view returns (uint256) {
        if (borrower != address(idleStrategyManager)){
            if (!_borrowersSet.contains(borrower)) {
                return 0;
            }
        }
        
        return debtToken.balanceOf(borrower);
    }

    /**
     * @notice The current max debt ceiling that a borrower is allowed to borrow up to.
     * @dev Represented as `PRECISION` decimals
     */
    function borrowerDebtCeiling(address borrower) external override view returns (uint256) {
        return borrowers[borrower].debtCeiling;
    }

    /**
     * @notice The total available balance of `asset` available to be withdrawn or borrowed
     * @dev The minimum of:
     *    - The `asset` available in the idle strategy manager, and 
     *    - The available global capacity remaining
     * Represented in the underlying asset's decimals (eg 6dp for USDC)
     */
    function totalAvailableToWithdraw() public override view returns (uint256) {
        uint256 _globalAvailable = _globalAvailableToBorrow();                       // asset's dp
        uint256 _idleStrategyAvailable = idleStrategyManager.availableToWithdraw();  // asset's dp
        return _idleStrategyAvailable < _globalAvailable ? _idleStrategyAvailable : _globalAvailable;
    }

    /**
     * @notice Calculate the amount remaining that can be borrowed for a particular borrower.
     * The min of the global available capacity and the remaining capacity given that borrower's
     * existing debt and configured ceiling.
     * @dev Represented in the underlying asset's decimals (eg 6dp for USDC)
     */
    function availableToBorrow(address borrower) external override view returns (uint256) {
        return _availableToBorrow(borrower, _getBorrowerConfig(borrower));
    }

    /**
     * @notice Calculate the net interest rate for a given borrower
     * The maximum of the 'global' interest rate and this borrowers specific interest rate
     * @dev It is possible for this to be >100% as debt grows over time
     * 1e18 represents an APY of 100%
     */
    function calculateCombinedInterestRate(address borrower) external override view returns (uint96) {
        return _calculateCombinedInterestRate(borrower, _getBorrowerConfig(borrower), false);
    }

    /**
     * @notice Calculate the global interest rate, based off the current global utilisation ratio
     * @dev It is possible for this to be >100% as debt grows over time
     * 1e18 represents an APY of 100%
     */
    function calculateGlobalInterestRate() external override view returns (uint96) {
        return _calculateGlobalInterestRate(false);
    }

    /**
     * @notice The global utilisation ratio across all borrowers
     * global UR = total borrower debt / oToken circulating supply
     * This will:
     *   - Increase when the debt increases (new borrow or interest), decrease on debt repayments (numerator)
     *   - Increase on user exits, decrease on user deposits or when new oToken is minted as new reserves
     *     for newly accrued iUSDC (denominator)
     * @dev 1e18 represents a ratio of 1
     */
    function globalUtilisationRatio() public override view returns (uint256) {
        // Equivalent logic here to `_globalAvailableToBorrow()`
        uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp
        uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

        if (_totalBorrowerDebt == 0) {
            return 0;
        } else if (_totalBorrowerCeiling == 0) {
            return type(uint256).max;
        } else {
            return _totalBorrowerDebt.mulDiv(
                PRECISION, 
                _totalBorrowerCeiling, 
                OrigamiMath.Rounding.ROUND_UP
            );
        }
    }

    /**
     * @notice The total debt across all borrowers (excluding the idle strategy manager)
     * @dev Accrued debt data may be slightly stale for each borrower & idle strategy
     * So periodic checkpoints are required.
     * @dev Represented as `PRECISION` decimals. 100e18 represents 100 debt tokens
     */
    function totalBorrowerDebt() public override view returns (uint256) {
        address[] memory _debtorsToExclude = new address[](1);
        _debtorsToExclude[0] = address(idleStrategyManager);
        return debtToken.totalSupplyExcluding(_debtorsToExclude);
    }

    /**
     * @notice Calculate the latest borrower specific interest rate, using the latest utilisation
     * ratio of that borrower
     * @dev Represented in `PRECISION` decimal places. 1e18 represents an APY of 100%
     */
    function calculateBorrowerInterestRate(address borrower) external override view returns (uint96) {
        return _calculateBorrowerInterestRate(borrower, _getBorrowerConfig(borrower), false);
    }

    /**
     * @notice The utilisation ratio for a given borrower
     * borrower specific UR = debt balance / debt ceiling
     * @dev Represented in `PRECISION` decimal places. 1e18 represents a ratio of 1
     */
    function borrowerUtilisationRatio(address borrower) external override view returns (uint256) {
        return _borrowerUtilisationRatio(borrower, _getBorrowerConfig(borrower));
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _getBorrowerConfig(address borrower) private view returns (BorrowerConfig storage) {
        if (!_borrowersSet.contains(borrower)) revert BorrowerNotEnabled();
        return borrowers[borrower];
    }

    /**
     * @notice Checkpoint the debtToken balances for the idleStrategy manager
     * and a borrower in order to get a more up to date global utilisation ratio
     */
    function _checkpointDebtTokenBalances(address borrower) private {
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (address(idleStrategyManager), borrower);
        debtToken.checkpointDebtorsInterest(_debtors);
    }

    function _borrow(
        address borrower, 
        address recipient, 
        BorrowerConfig storage borrowerConfig, 
        uint256 borrowAmount
    ) private {
        if (borrowAmount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (globalBorrowPaused) revert BorrowPaused();
        if (borrowerConfig.borrowPaused) revert BorrowPaused();

        // Check this borrow amount against the circuit breaker
        circuitBreakerProxy.preCheck(
            address(asset),
            borrowAmount
        );

        emit Borrow(borrower, recipient, borrowAmount);

        // Transfer the debt token amount from the idle strategy to the borrower
        // No allowances needed for debtToken, since only minters can transfer.
        debtToken.safeTransferFrom(address(idleStrategyManager), borrower, borrowAmount.scaleUp(_assetScalar));

        // Pull funds from idle strategy and send to recipient
        // If there aren't enough idle funds to cover this amount then it will revert.
        idleStrategyManager.withdraw(borrowAmount, recipient);

        // Refresh the borrower's interest rate.
        // Verify that both the global and borrower utilisation is <=100%
        _refreshBorrowersInterestRate(borrower, borrowerConfig, true);
    }

    function _repay(
        address from, 
        address borrower, 
        BorrowerConfig storage borrowerConfig,
        uint256 repayAmount,
        uint256 debtToTransfer
    ) private {
        if (globalRepayPaused) revert RepayPaused();       
        if (borrowerConfig.repayPaused) revert RepayPaused();
        emit Repay(borrower, from, repayAmount);

        // Transfer the debt token amount from the borrower to the idle strategy
        // No allowances needed for debtToken, since only minters can transfer.
        debtToken.safeTransferFrom(borrower, address(idleStrategyManager), debtToTransfer);

        // Refresh the borrower's interest rate.
        // No need to verify that either the global or borrower utilisation is <=100%
        // on a repayment.
        _refreshBorrowersInterestRate(borrower, borrowerConfig, false);

        // Transfer the idle funds in and allocate into the idle strategy
        asset.safeTransferFrom(from, address(this), repayAmount);
        idleStrategyManager.allocate(repayAmount);
    }

    /**
     * @notice Calculate the global available amount which would bring the
     * utilisation ratio to 100%
     * @dev In the underlying asset's decimals (eg 6dp for USDC)
     */
    function _globalAvailableToBorrow() private view returns (uint256) {
        // Equivalent logic here to `globalUtilisationRatio()`
        uint256 _totalBorrowerDebt = totalBorrowerDebt();           // debt in 18dp
        uint256 _totalBorrowerCeiling = oToken.circulatingSupply(); // oToken in 18dp

        // This scaleDown intentionally rounds down (so it's not in the borrower's benefit)
        return _totalBorrowerCeiling > _totalBorrowerDebt 
            ? (_totalBorrowerCeiling - _totalBorrowerDebt).scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN)
            : 0;
    }

    /**
     * @notice Calculate the amount remaining that can be borrowed for a particular borrower.
     * The min of the global available capacity and the remaining capacity given that borrower's
     * existing debt and configured ceiling.
     * @dev Represented in the underlying asset's decimals (eg 6dp for USDC)
     */
    function _availableToBorrow(
        address borrower,
        BorrowerConfig storage borrowerConfig
    ) private view returns (uint256) {
        // Calculate the specific borrower's max available
        uint256 _borrowerAmount;   // asset's dp
        {
            // Equivalent logic here to `_borrowerUtilisationRatio()`
            uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp
            uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp
            unchecked {
                _borrowerAmount = _borrowerDebtCeiling > _borrowerDebtBalance
                    // This scaleDown intentionally rounds down (so it's not in the borrower's benefit)
                    ? (_borrowerDebtCeiling - _borrowerDebtBalance).scaleDown(_assetScalar, OrigamiMath.Rounding.ROUND_DOWN)
                    : 0;
            }
        }

        // Also cap to the remaining capacity in the circuit breaker (asset's dp)
        uint256 _cbAvailable = circuitBreakerProxy.available(address(asset), address(this));
        if (_cbAvailable < _borrowerAmount) {
            _borrowerAmount = _cbAvailable;
        }

        uint256 _globalAmount = totalAvailableToWithdraw(); // asset's dp

        // Return the min of the globally available and
        // this borrower's specific amount
        return _globalAmount < _borrowerAmount
            ? _globalAmount
            : _borrowerAmount;
    }

    /**
     * @notice Refresh the interest rate for a set of borrowers, using the latest utilisation rates.
     */
    function _refreshBorrowersInterestRate(
        address borrower, 
        BorrowerConfig storage borrowerConfig, 
        bool validateUR
    ) private {
        uint96 rate = _calculateCombinedInterestRate(borrower, borrowerConfig, validateUR);
        debtToken.setInterestRate(borrower, rate);
    }

    /**
     * @notice Calculate the net interest rate for a given borrower
     * @dev The maximum of the 'global' interest rate and this borrowers specific interest rate
     * Represented in `PRECISION` decimals. 1e18 represents 100%
     */
    function _calculateCombinedInterestRate(
        address borrower, 
        BorrowerConfig storage borrowerConfig, 
        bool validateUR
    ) private view returns (uint96) {
        // This is using the up to date total of debt for this borrower
        uint96 _borrowerIR = _calculateBorrowerInterestRate(borrower, borrowerConfig, validateUR);
        
        // This is using the latest checkpoint of the debt
        // This may be slightly less due to accrued debt since the last checkpoint
        // But only means the global IR is ever so slightly less than it could be - so not an issue.
        // Checkpoints (or normal borrow/repayments) will happen frequently
        uint96 _globalIR = _calculateGlobalInterestRate(validateUR);

        return _globalIR > _borrowerIR
            ? _globalIR
            : _borrowerIR;
    }

    /**
     * @notice Calculate the global interest rate, based off the current global utilisation ratio
     * @dev Represented in `PRECISION` decimals. 1e18 represents 100%
     * @param validateUR Whether to revert if the utilisation ratio is greater than 100%
     */
    function _calculateGlobalInterestRate(bool validateUR) private view returns (uint96) {
        uint256 ur = globalUtilisationRatio();
        if (validateUR) {
            if (ur > PRECISION) revert AboveMaxUtilisation(ur);
        }
        return globalInterestRateModel.calculateInterestRate(ur);
    }

    /**
     * @notice Calculate the latest borrower specific interest rate, using the latest utilisation
     * ratio of that borrower
     * @dev Represented in `PRECISION` decimal places. 1e18 represents 100%
     */
    function _calculateBorrowerInterestRate(
        address borrower, 
        BorrowerConfig storage borrowerConfig, 
        bool validateUR
    ) private view returns (uint96) {
        uint256 ur = _borrowerUtilisationRatio(borrower, borrowerConfig);
        if (validateUR) {
            if (ur > PRECISION) revert AboveMaxUtilisation(ur);
        }        
        return borrowerConfig.interestRateModel.calculateInterestRate(ur);
    }
    
    /**
     * @notice The utilisation ratio for a given borrower
     * borrower specific UR = debt balance / debt ceiling
     * Represented in `PRECISION` decimal places. 1e18 represents a ratio of 1
     */
    function _borrowerUtilisationRatio(
        address borrower, 
        BorrowerConfig storage borrowerConfig
    ) private view returns (uint256) {
        // Equivalent logic here to within `_availableToBorrow()`, except the
        // global circuit breaker is not included in the denominator
        uint256 _borrowerDebtBalance = debtToken.balanceOf(borrower); // 18dp
        uint256 _borrowerDebtCeiling = borrowerConfig.debtCeiling;      // 18 dp

        if (_borrowerDebtBalance == 0) {
            return 0;
        } else if (_borrowerDebtCeiling == 0) {
            return type(uint256).max;
        } else {
            return _borrowerDebtBalance.mulDiv(
                PRECISION,
                _borrowerDebtCeiling,
                OrigamiMath.Rounding.ROUND_UP
            );
        }
    }

    modifier onlySupplyManager() {
        if (msg.sender != address(supplyManager)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}