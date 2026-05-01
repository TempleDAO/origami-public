pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/borrowAndLend/IOrigamiBorrowAndLendWithLeverage.sol)

import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`, for a given `positionOwner`
 */
interface IOrigamiBorrowAndLendWithLeverage is IOrigamiBorrowAndLend {
    
    /**
     * @notice Increase the leverage of the existing position, by supplying `supplyToken` as collateral
     * and borrowing `borrowToken` and swapping that back to `supplyToken`
     * @dev The totalCollateralSupplied may include any surplus after swapping from the debt to collateral
     */
    function increaseLeverage(
        uint256 supplyCollateralAmount,
        uint256 borrowAmount,
        bytes memory swapData,
        uint256 supplyCollateralSurplusThreshold
    ) external returns (uint256 totalCollateralSupplied);

    /**
     * @notice Decrease the leverage of the existing position, by repaying `borrowToken`,
     * withdrawing `supplyToken` collateral and swapping that back to `borrowToken`
     */
    function decreaseLeverage(
        uint256 repayAmount,
        uint256 withdrawCollateralAmount,
        bytes memory swapData,
        uint256 repaySurplusThreshold
    ) external returns (
        uint256 debtRepaidAmount,
        uint256 surplusDebtRepaid
    );

}