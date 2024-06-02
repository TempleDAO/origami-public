pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CompoundedInterest } from "contracts/libraries/CompoundedInterest.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

contract MockEscrow {
    using SafeERC20 for IERC20;

    function pullToken(
        address _token,
        address _to,
        uint256 _amount
    ) external {
        IERC20(_token).safeTransfer(_to, _amount);
    }
}

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 */
contract MockBorrowAndLend is IOrigamiBorrowAndLend, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    error ExceededLtv(uint256 current, uint256 max);

    /**
     * @notice The token supplied as collateral
     */
    address public override immutable supplyToken;

    /**
     * @notice The token which is borrowed
     */
    address public override immutable borrowToken;

    /**
     * @notice The approved owner of the borrow/lend position
     */
    address public override positionOwner;
   
    /// @notice The supplied balance + accrued interest of the positionOwner
    uint256 private _supplyBalance;

    /// @notice The debt + accrued interest of the positionOwner
    uint256 private _debtBalance;

    /// @notice The max LTV of this fake money market
    uint256 public maxLtvBps;

    /// @notice The max supply of this fake money market
    uint256 public supplyCap;

    /// @notice converting supply -> borrow for LTV check
    IOrigamiOracle public oracle;

    MockEscrow public immutable escrow;

    /**
     * @dev Factor when converting the LTV (basis points) to an Origami Assets/Liabilities (1e18)
     */
    uint256 private constant LTV_TO_AL_FACTOR = 1e22;

    struct AccumulatorData {
        uint256 accumulatorUpdatedAt;
        uint256 accumulator;
        uint256 checkpoint;
        uint96 interestRate;
    }

    AccumulatorData public supplyAccumulatorData;
    AccumulatorData public borrowAccumulatorData;

    constructor(
        address _initialOwner,
        address _supplyToken,
        address _borrowToken,
        uint256 _maxLtvBps,
        uint256 _supplyCap,
        uint96 _supplyInterestRate,
        uint96 _borrowInterestRate,
        address _oracle
    ) OrigamiElevatedAccess(_initialOwner) {
        supplyToken = _supplyToken;
        borrowToken = _borrowToken;
        supplyCap = _supplyCap;
        maxLtvBps = _maxLtvBps;
        oracle = IOrigamiOracle(_oracle);
        escrow = new MockEscrow();

        supplyAccumulatorData = AccumulatorData(block.timestamp, 1e27, 0, _supplyInterestRate);
        borrowAccumulatorData = AccumulatorData(block.timestamp, 1e27, 0, _borrowInterestRate);
    }

    /**
     * @notice Set the position owner who can borrow/lend via this contract
     */
    function setPositionOwner(address account) external override onlyElevatedAccess {
        positionOwner = account;
        emit PositionOwnerSet(account);
    }

    function setConfig(uint256 _maxLtvBps, uint256 _supplyCap, address _oracle) external onlyElevatedAccess {
        _checkpoint(supplyAccumulatorData);
        _checkpoint(borrowAccumulatorData);

        maxLtvBps = _maxLtvBps;
        supplyCap = _supplyCap;
        oracle = IOrigamiOracle(_oracle);
    }

    function updateRates(uint96 supplyRate, uint96 borrowRate) external onlyElevatedAccess {
        _checkpoint(supplyAccumulatorData);
        supplyAccumulatorData.interestRate = supplyRate;
        
        _checkpoint(borrowAccumulatorData);
        borrowAccumulatorData.interestRate = borrowRate;
    }

    /**
     * @notice Supply tokens as collateral
     */
    function supply(
        uint256 supplyAmount
    ) external override onlyPositionOwnerOrElevated {
        _supply(supplyAmount);
    }

    /**
     * @notice Withdraw collateral tokens to recipient
     */
    function withdraw(
        uint256 withdrawAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated returns (uint256 amountWithdrawn) {
        amountWithdrawn = _withdraw(withdrawAmount, recipient);
    }

    /**
     * @notice Borrow tokens and send to recipient
     */
    function borrow(
        uint256 borrowAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated {
        _borrow(borrowAmount, recipient);
    }

    /**
     * @notice Repay debt. 
     * @dev `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repay(
        uint256 repayAmount
    ) external override onlyPositionOwnerOrElevated returns (uint256 debtRepaidAmount) {
        debtRepaidAmount = _repay(repayAmount);
    }

    /**
     * @notice Repay debt and withdraw collateral in one step
     * @dev `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repayAndWithdraw(
        uint256 repayAmount, 
        uint256 withdrawAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated returns (uint256 debtRepaidAmount, uint256 withdrawnAmount) {
        debtRepaidAmount = _repay(repayAmount);
        withdrawnAmount = _withdraw(withdrawAmount, recipient);
    }

    /**
     * @notice Supply collateral and borrow in one step
     */
    function supplyAndBorrow(
        uint256 supplyAmount, 
        uint256 borrowAmount, 
        address recipient
    ) external override onlyPositionOwnerOrElevated {
        _supply(supplyAmount);
        _borrow(borrowAmount, recipient);
    }

    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {       
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }
    
    /**
     * @notice The current (manually tracked) balance of tokens supplied
     */
    function suppliedBalance() public override view returns (uint256) {
        return _updatedBalance(supplyAccumulatorData);
    }

    /**
     * @notice The current debt balance of tokens borrowed
     */
    function debtBalance() public override view returns (uint256) {
        return _updatedBalance(borrowAccumulatorData);
    }

    /**
     * @notice Whether a given Assets/Liabilities Ratio is safe, given the upstream
     * money market parameters
     */
    function isSafeAlRatio(uint256 alRatio) external override view returns (bool) {
        // Convert the Aave LTV to A/L (with 1e18 precision) and compare
        unchecked {
            return alRatio >= LTV_TO_AL_FACTOR / maxLtvBps;
        }
    }

    /**
     * @notice How many `supplyToken` are available to withdraw from collateral
     * from the entire protocol, assuming this contract has fully paid down its debt
     */
    function availableToWithdraw() external override view returns (uint256) {
        return IERC20(supplyToken).balanceOf(address(escrow));
    }

    /**
     * @notice How many `borrowToken` are available to borrow
     * from the entire protocol
     */
    function availableToBorrow() external override view returns (uint256) {
        return IERC20(borrowToken).balanceOf(address(escrow));
    }

    /**
     * @notice How much more capacity is available to supply
     */
    function availableToSupply() external override view returns (
        uint256 _supplyCap,
        uint256 available
    ) {
        _supplyCap = supplyCap;
        uint256 _utilised = IERC20(supplyToken).balanceOf(address(escrow));
        unchecked {
            available = _supplyCap > _utilised ? _supplyCap - _utilised : 0;
        }
    }

    function getSupplyCache() external view returns (AccumulatorData memory c) {
        (c,) = _getCache(supplyAccumulatorData);
    }

    function getBorrowCache() external view returns (AccumulatorData memory c) {
        (c,) = _getCache(borrowAccumulatorData);
    }

    function _getCache(AccumulatorData storage data) internal view returns (AccumulatorData memory cache, bool dirty) {
        cache.accumulatorUpdatedAt = data.accumulatorUpdatedAt;
        cache.accumulator = data.accumulator;
        cache.checkpoint = data.checkpoint;
        cache.interestRate = data.interestRate;

        // Only compound if we're on a new block
        uint256 _timeElapsed;
        unchecked {
            _timeElapsed = block.timestamp - cache.accumulatorUpdatedAt;
        }

        if (_timeElapsed > 0) {
            dirty = true;

            // Compound the accumulator
            uint256 newAccumulator = CompoundedInterest.continuouslyCompounded(
                cache.accumulator,
                _timeElapsed,
                cache.interestRate
            );

            cache.checkpoint = newAccumulator.mulDiv(
                cache.checkpoint,
                cache.accumulator,
                OrigamiMath.Rounding.ROUND_UP
            );

            cache.accumulator = newAccumulator;
        }
    }

    function _updatedBalance(AccumulatorData storage data) internal view returns (uint256 newBalance) {
        (AccumulatorData memory cache,) = _getCache(data);
        return cache.checkpoint;
    }

    function _checkpoint(AccumulatorData storage data) internal returns (uint256) {
        (AccumulatorData memory cache, bool dirty) = _getCache(data);
        if (dirty) {
            data.accumulatorUpdatedAt = block.timestamp;
            data.accumulator = cache.accumulator;
            data.checkpoint = cache.checkpoint;
        }
        return cache.checkpoint;
    }

    function _checkLtv(uint256 supplyBal, uint256 debtBal) internal view {
        if (debtBal == 0) return;
        if (supplyBal == 0) revert ExceededLtv(type(uint256).max, maxLtvBps);

        // Convert the supplied amount (eg wstETH) into the debt terms (eg wETH)
        uint256 suppliedAsDebt = oracle.convertAmount(
            supplyToken, 
            supplyBal, 
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );

        uint256 currentLtvBps = debtBal.mulDiv(
            OrigamiMath.BASIS_POINTS_DIVISOR, 
            suppliedAsDebt, 
            OrigamiMath.Rounding.ROUND_UP
        );

        if (currentLtvBps > maxLtvBps) revert ExceededLtv(currentLtvBps, maxLtvBps);
    }

    function _supply(uint256 supplyAmount) internal {
        IERC20(supplyToken).safeTransfer(address(escrow), supplyAmount);
        uint256 newSupplyBalance = _checkpoint(supplyAccumulatorData);

        supplyAccumulatorData.checkpoint = newSupplyBalance + supplyAmount;
    }

    function _withdraw(uint256 withdrawAmount, address recipient) internal returns (uint256 amountWithdrawn) {
        uint256 newSupplyBalance = _checkpoint(supplyAccumulatorData);
        amountWithdrawn = withdrawAmount > newSupplyBalance ? newSupplyBalance : withdrawAmount;

        newSupplyBalance -= amountWithdrawn;
        supplyAccumulatorData.checkpoint = newSupplyBalance;

        // Check LTV
        _checkLtv(newSupplyBalance, _updatedBalance(borrowAccumulatorData));

        escrow.pullToken(supplyToken, recipient, amountWithdrawn);
    }

    function _borrow(uint256 borrowAmount, address recipient) internal {
        uint256 newDebtBalance = _checkpoint(borrowAccumulatorData);
        newDebtBalance += borrowAmount;
        borrowAccumulatorData.checkpoint = newDebtBalance;

        // Check LTV
        _checkLtv(_updatedBalance(supplyAccumulatorData), newDebtBalance);

        escrow.pullToken(borrowToken, recipient, borrowAmount);
    }
    
    function _repay(uint256 repayAmount) internal returns (uint256 debtRepaidAmount) {
        uint256 newDebtBalance = _checkpoint(borrowAccumulatorData);
        debtRepaidAmount = repayAmount > newDebtBalance ? newDebtBalance : repayAmount;
        newDebtBalance -= debtRepaidAmount;
        borrowAccumulatorData.checkpoint = newDebtBalance;

        IERC20(borrowToken).safeTransfer(address(escrow), debtRepaidAmount);
    }

    /**
     * @dev Only the positionOwner or Elevated Access is allowed to call.
     */
    modifier onlyPositionOwnerOrElevated() {
        if (msg.sender != address(positionOwner) && !isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
