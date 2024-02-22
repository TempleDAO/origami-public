pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";

/* solhint-disable immutable-vars-naming */

/// @notice A very cut down implementation of IOrigamiLendingClerk
/// in order to mock for LovToken tests
contract DummyLendingClerk /* is IOrigamiLendingClerk */ {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /**
     * @notice The asset which users supply
     * eg USDC for oUSDC
     */
    IERC20 public immutable asset;

    /**
     * @notice The token issued to borrowers or idle strategy for the use of 
     * the collateral
     * @dev Not actually minted in this dummy lending clerk, but required for
     * decimals metadata
     */
    IOrigamiDebtToken public immutable debtToken;

    // USDC -> DAI needs to scale up by 12
    uint256 public constant ASSET_TO_DEBT_SCALAR = 1e12;

    /**
     * @notice A borrower's current debt as of now
     * @dev Represented as `PRECISION` decimals
     */
    mapping(address borrower => uint256 debt) public borrowerDebt;

    constructor(
        address _asset,
        address _debtToken
    ) {
        asset = IERC20(_asset);
        debtToken = IOrigamiDebtToken(_debtToken);
    }

    /**
     * @notice The supply manager deposits `asset`, which
     * allocates the funds to the idle strategy and mints `debtToken`
     * @param amount The amount to deposit in `asset` decimal places, eg 6dp for USDC
     */
    function deposit(uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice The supply manager withdraws asset, which pulls the `asset` from 
     * the idle strategy and burns the `debtToken`
     * @dev Cannot pull more than the global amount available left to borrow
     * @param amount The amount to withdraw in `asset` decimal places, eg 6dp for USDC
     * @param recipient The receiver of the `asset` withdraw
     */
    function withdraw(uint256 amount, address recipient) external {
        asset.safeTransfer(recipient, amount);
    }

    /**
     * @notice An approved borrower calls to request more funding.
     * @dev This will revert if the borrower requests more stables than it's able to borrow.
     * `debtToken` will be minted 1:1 for the amount of asset borrowed
     * @param amount The amount to borrow in `asset` decimal places, eg 6dp for USDC
     * @param recipient The receiving address of the `asset` tokens
     */
    function borrow(uint256 amount, address recipient) external {
        asset.safeTransfer(recipient, amount);
        borrowerDebt[msg.sender] += amount.scaleUp(ASSET_TO_DEBT_SCALAR);
    }

    /**
     * @notice Paydown debt for a borrower. This will pull the asset from the sender, 
     * and will burn the equivalent amount of debtToken from the borrower.
     * @dev The amount actually repaid is capped to the oustanding debt balance such
     * that it's not possible to overpay. Therefore this function can also be used to repay the entire debt.
     * @param amount The amount to repay in `asset` decimal places, eg 6dp for USDC
     * @param borrower The borrower to repay on behalf of
     */
    function repay(uint256 amount, address borrower) external returns (uint256 amountRepaid) {
        // Scaled up to the debt decimals
        uint256 _scaledAmount = amount.scaleUp(ASSET_TO_DEBT_SCALAR);

        // Borrower cannot repay more debt than has been accrued
        uint256 _debtBalance = borrowerDebt[borrower];
        amountRepaid = _scaledAmount > _debtBalance ? _debtBalance : _scaledAmount;

        asset.safeTransferFrom(
            msg.sender, 
            address(this), 
            amountRepaid.scaleDown(ASSET_TO_DEBT_SCALAR, OrigamiMath.Rounding.ROUND_UP)
        );

        unchecked {
            borrowerDebt[borrower] = _debtBalance - amountRepaid;
        }
    }

    /**
     * @notice The total available balance of `asset` available to be withdrawn or borrowed
     * @dev The minimum of:
     *    - The `asset` available in the idle strategy manager, and 
     *    - The available global capacity remaining
     * Represented in the underlying asset's decimals (eg 6dp for USDC)
     */
    function totalAvailableToWithdraw() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
