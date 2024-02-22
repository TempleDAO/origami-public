pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol)

/**
 * @notice An Origami abstraction over a borrow/lend money market for
 * a single `supplyToken` and a single `borrowToken`, for a given `positionOwner`
 */
interface IOrigamiBorrowAndLend {
    event PositionOwnerSet(address indexed account);
    event SurplusDebtReclaimed(uint256 amount, address indexed recipient);

    /**
     * @notice Set the position owner who can borrow/lend via this contract
     */
    function setPositionOwner(address account) external;

    /**
     * @notice Supply tokens as collateral
     */
    function supply(
        uint256 supplyAmount
    ) external;

    /**
     * @notice Withdraw collateral tokens to recipient
     */
    function withdraw(
        uint256 withdrawAmount, 
        address recipient
    ) external returns (uint256 amountWithdrawn);

    /**
     * @notice Borrow tokens and send to recipient
     */
    function borrow(
        uint256 borrowAmount,
        address recipient
    ) external;

    /**
     * @notice Repay debt. 
     * @dev `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repay(
        uint256 repayAmount
    ) external returns (uint256 debtRepaidAmount);

    /**
     * @notice Repay debt and withdraw collateral in one step
     * @dev `debtRepaidAmount` return parameter will be capped to the outstanding debt amount.
     * Any surplus debtTokens (if debt fully repaid) will remain in this contract
     */
    function repayAndWithdraw(
        uint256 repayAmount, 
        uint256 withdrawAmount, 
        address recipient
    ) external returns (
        uint256 debtRepaidAmount,
        uint256 withdrawnAmount
    );

    /**
     * @notice Supply collateral and borrow in one step
     */
    function supplyAndBorrow(
        uint256 supplyAmount, 
        uint256 borrowAmount, 
        address recipient
    ) external;

    /**
     * @notice Reclaim surplus borrowToken which cannot be repaid
     */
    function reclaimSurplusDebt(uint256 amount, address recipient) external;

    /**
     * @notice The approved owner of the borrow/lend position
     */
    function positionOwner() external view returns (address);

    /**
     * @notice The token supplied as collateral
     */
    function supplyToken() external view returns (address);

    /**
     * @notice The token which is borrowed
     */
    function borrowToken() external view returns (address);

    /**
     * @notice The current (manually tracked) balance of tokens supplied
     */
    function suppliedBalance() external view returns (uint256);

    /**
     * @notice The current debt balance of tokens borrowed
     */
    function debtBalance() external view returns (uint256);

    /**
     * @notice Whether a given Assets/Liabilities Ratio is safe, given the upstream
     * money market parameters
     */
    function isSafeAlRatio(uint256 alRatio) external view returns (bool);

    /**
     * @notice How many `supplyToken` are available to withdraw from collateral
     * from the entire protocol
     */
    function availableToWithdraw() external view returns (uint256);

    /**
     * @notice How much more capacity is available to supply
     */
    function availableToSupply() external view returns (
        uint256 supplyCap,
        uint256 utilised,
        uint256 available
    );
}