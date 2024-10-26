pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { WadRayMath as AaveWadRayMath} from "@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol";
import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IAToken as IAaveAToken } from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import { IAaveV3RewardsController } from "contracts/interfaces/external/aave/aave-v3-periphery/IAaveV3RewardsController.sol";

import { IOrigamiAaveV3BorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiAaveV3BorrowAndLend.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`.
 * This is an Aave V3 specific interface, borrowing using variable debt only
 */
contract OrigamiAaveV3BorrowAndLend is IOrigamiAaveV3BorrowAndLend, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    /**
     * @notice The Aave/Spark pool contract
     */
    IAavePool public override aavePool;

    /**
     * @notice The token supplied as collateral
     */
    address public override immutable supplyToken;

    /**
     * @notice The token which is borrowed
     */
    address public override immutable borrowToken;

    /**
     * @notice The Aave/Spark rebasing aToken received when supplying `supplyToken`
     */
    IAaveAToken public override immutable aaveAToken;

    /**
     * @notice The Aave/Spark rebasing variable debt token received when borrowing `debtToken`
     */
    IERC20Metadata public override immutable aaveDebtToken;

    /**
     * @notice The approved owner of the borrow/lend position
     */
    address public override positionOwner;
    
    /**
     * @notice Only use the Aave/Spark variable interest, not fixed
     */
    uint256 private constant INTEREST_RATE_MODE = uint256(AaveDataTypes.InterestRateMode.VARIABLE);

    /**
     * @notice The referral code used when supplying/borrowing in Aave/Spark
     */
    uint16 public override referralCode = 0;

    /**
     * @dev The number of Aave/Spark aToken shares are tracked manually rather than relying on
     * balanceOf
     */
    uint256 private _aTokenShares;

    /**
     * @dev Factor when converting the Aave LTV (basis points) to an Origami Assets/Liabilities (1e18)
     */
    uint256 private constant LTV_TO_AL_FACTOR = 1e22;

    constructor(
        address _initialOwner,
        address _supplyToken,
        address _borrowToken,
        address _aavePool,
        uint8 _defaultEMode
    ) OrigamiElevatedAccess(_initialOwner) {
        supplyToken = _supplyToken;
        borrowToken = _borrowToken;
        
        aavePool = IAavePool(_aavePool);
        aaveAToken = IAaveAToken(aavePool.getReserveData(supplyToken).aTokenAddress);
        aaveDebtToken = IERC20Metadata(aavePool.getReserveData(_borrowToken).variableDebtTokenAddress);

        // Approve the supply and borrow to the Aave/Spark pool upfront
        IERC20(supplyToken).forceApprove(address(aavePool), type(uint256).max);
        IERC20(borrowToken).forceApprove(address(aavePool), type(uint256).max);

        // Initate e-mode on the Aave/Spark pool if required
        if (_defaultEMode != 0) {
            aavePool.setUserEMode(_defaultEMode);
        }
    }

    /**
     * @notice Set the position owner who can borrow/lend via this contract
     */
    function setPositionOwner(address account) external override onlyElevatedAccess {
        positionOwner = account;
        emit PositionOwnerSet(account);
    }

    /**
     * @notice Set the Aave/Spark referral code
     */
    function setReferralCode(uint16 code) external override onlyElevatedAccess {
        referralCode = code;
        emit ReferralCodeSet(code);
    }

    /**
     * @notice Allow the use of `supplyToken` as collateral within Aave/Spark
     */
    function setUserUseReserveAsCollateral(bool useAsCollateral) external override onlyElevatedAccess {
        aavePool.setUserUseReserveAsCollateral(supplyToken, useAsCollateral);
    }

    /**
     * @notice Update the e-mode category for the pool
     */
    function setEModeCategory(uint8 categoryId) external override onlyElevatedAccess {
        aavePool.setUserEMode(categoryId);
    }

    /**
     * @notice Update the Aave/Spark pool
     */
    function setAavePool(address pool) external override onlyElevatedAccess {
        if (pool == address(0)) revert CommonEventsAndErrors.InvalidAddress(pool);

        address oldPool = address(aavePool);
        if (pool == oldPool) revert CommonEventsAndErrors.InvalidAddress(pool);

        emit AavePoolSet(pool);
        aavePool = IAavePool(pool);

        // Reset allowance to old Aave/Spark pool
        IERC20(supplyToken).forceApprove(oldPool, 0);
        IERC20(borrowToken).forceApprove(oldPool, 0);

        // Approve the supply and borrow to the new Aave/Spark pool upfront
        IERC20(supplyToken).forceApprove(pool, type(uint256).max);
        IERC20(borrowToken).forceApprove(pool, type(uint256).max);
    }

    /**
     * @notice Elevated access can claim rewards, from a nominated rewards controller.
     * @param rewardsController The aave-v3-periphery RewardsController
     * @param assets The list of assets to check eligible distributions before claiming rewards
     * @param to The address that will be receiving the rewards
     * @return rewardsList List of addresses of the reward tokens
     * @return claimedAmounts List that contains the claimed amount per reward, following same order as "rewardList"
     */
    function claimAllRewards(
        address rewardsController,
        address[] calldata assets,
        address to
    ) external override onlyElevatedAccess returns (
        address[] memory rewardsList, 
        uint256[] memory claimedAmounts
    ) {
        // Event emitted within rewards controller.
        return IAaveV3RewardsController(rewardsController).claimAllRewards(
            assets,
            to
        );
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
     * @dev Set `withdrawAmount` to type(uint256).max in order to withdraw the whole balance
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
     * @dev If `repayAmount` is set higher than the actual outstanding debt balance, it will be capped
     * to that outstanding debt balance
     * `debtRepaidAmount` return parameter will be capped to the outstanding debt balance.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repay(
        uint256 repayAmount
    ) external override onlyPositionOwnerOrElevated returns (uint256 debtRepaidAmount) {
        debtRepaidAmount = _repay(repayAmount);
    }

    /**
     * @notice Repay debt and withdraw collateral in one step
     * @dev If `repayAmount` is set higher than the actual outstanding debt balance, it will be capped
     * to that outstanding debt balance
     * Set `withdrawAmount` to type(uint256).max in order to withdraw the whole balance
     * `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
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

    /**
     * @notice Recover accidental donations, or surplus aaveAToken borrowToken.
     * `aaveAToken` can only be recovered for amounts greater than the internally tracked balance of shares.
     * `borrowToken` are only expected on shutdown if there are surplus tokens after full repayment.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);

        if (token == address(aaveAToken)) {
            // Ensure there are still enough aToken shares to cover the internally tracked
            // balance
            uint256 _sharesAfter = aaveAToken.scaledBalanceOf(address(this));
            if (_aTokenShares > _sharesAfter) {
                revert CommonEventsAndErrors.InvalidAmount(token, amount);
            }
        }
    }
    
    /**
     * @notice The current (manually tracked) balance of tokens supplied
     */
    function suppliedBalance() public override view returns (uint256) {
        return AaveWadRayMath.rayMul(
            _aTokenShares, 
            aavePool.getReserveNormalizedIncome(supplyToken)
        );
    }

    /**
     * @notice The current debt balance of tokens borrowed
     */
    function debtBalance() public override view returns (uint256) {
        return aaveDebtToken.balanceOf(address(this));
    }

    /**
     * @notice Whether a given Assets/Liabilities Ratio is safe, given the upstream
     * money market parameters
     */
    function isSafeAlRatio(uint256 alRatio) external override view returns (bool) {
        // If in e-mode, then use the LTV from that category
        // Otherwise use the LTV from the reserve data
        uint256 _eModeId = aavePool.getUserEMode(address(this));

        // Our max LTV must be <= Aave's deposits LTV (not the liquidation LTV)
        uint256 _aaveLtv = _eModeId == 0
            ? aavePool.getConfiguration(supplyToken).getLtv()
            : aavePool.getEModeCategoryData(uint8(_eModeId)).ltv;

        // Convert the Aave LTV to A/L (with 1e18 precision) and compare
        // The A/L is considered safe if it's higher or equal to the upstream aave A/L
        unchecked {
            return alRatio >= LTV_TO_AL_FACTOR / _aaveLtv;
        }
    }

    /**
     * @notice How many `supplyToken` are available to withdraw from collateral
     * from the entire protocol, assuming this contract has fully paid down its debt
     */
    function availableToWithdraw() external override view returns (uint256) {
        return IERC20(supplyToken).balanceOf(address(aaveAToken));
    }

    /**
     * @notice How many `borrowToken` are available to borrow
     * from the entire protocol
     */
    function availableToBorrow() external override view returns (uint256 available) {
        AaveDataTypes.ReserveData memory _reserveData = aavePool.getReserveData(borrowToken);
        uint256 borrowCap = _reserveData.configuration.getBorrowCap() * (10 ** _reserveData.configuration.getDecimals());
        available = IERC20(borrowToken).balanceOf(_reserveData.aTokenAddress);

        if (borrowCap > 0 && borrowCap < available) {
            available = borrowCap;
        }
    }

    /**
     * @notice How much more capacity is available to supply
     */
    function availableToSupply() external override view returns (
        uint256 supplyCap,
        uint256 available
    ) {
        AaveDataTypes.ReserveData memory _reserveData = aavePool.getReserveData(supplyToken);

        // The supply cap needs to be scaled by decimals
        uint256 unscaledCap = _reserveData.configuration.getSupplyCap();
        if (unscaledCap == 0) return (type(uint256).max, type(uint256).max);  
        supplyCap = unscaledCap * (10 ** _reserveData.configuration.getDecimals());

        // The utilised amount is the scaledTotalSupply + any fees accrued to treasury
        // Then scaled by the normalised income.
        uint256 _utilised = AaveWadRayMath.rayMul(
            aavePool.getReserveNormalizedIncome(supplyToken),
            (
                aaveAToken.scaledTotalSupply() +
                _reserveData.accruedToTreasury
            )
        );

        unchecked {
            available = supplyCap > _utilised ? supplyCap - _utilised : 0;
        }
    }

    /**
     * @notice Returns the Aave/Spark account data
     * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
     * @return totalDebtBase The total debt of the user in the base currency used by the price feed
     * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
    */
    function debtAccountData() external override view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return aavePool.getUserAccountData(address(this));
    }

    function _supply(uint256 supplyAmount) internal {
        uint256 sharesBefore = aaveAToken.scaledBalanceOf(address(this));
        aavePool.supply(supplyToken, supplyAmount, address(this), referralCode);
        _aTokenShares = _aTokenShares + aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;
    }

    function _withdraw(uint256 withdrawAmount, address recipient) internal returns (uint256 amountWithdrawn) {
        uint256 sharesBefore = aaveAToken.scaledBalanceOf(address(this));
        amountWithdrawn = aavePool.withdraw(supplyToken, withdrawAmount, recipient);
        _aTokenShares = _aTokenShares + aaveAToken.scaledBalanceOf(address(this)) - sharesBefore;
    }

    function _borrow(uint256 borrowAmount, address recipient) internal {
        aavePool.borrow(borrowToken, borrowAmount, INTEREST_RATE_MODE, referralCode, address(this));
        IERC20(borrowToken).safeTransfer(recipient, borrowAmount);
    }
    
    function _repay(uint256 repayAmount) internal returns (uint256 debtRepaidAmount) {
        if (debtBalance() != 0) {
            debtRepaidAmount = aavePool.repay(borrowToken, repayAmount, INTEREST_RATE_MODE, address(this));
        }
    }

    /**
     * @dev Only the positionOwner or Elevated Access is allowed to call.
     */
    modifier onlyPositionOwnerOrElevated() {
        if (msg.sender != address(positionOwner)) {
            if (!isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        }
        _;
    }
}
