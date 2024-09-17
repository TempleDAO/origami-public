pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (periphery/OrigamiBorrowLendMigrator.sol)

import { IOrigamiFlashLoanReceiver } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol";
import { IOrigamiFlashLoanProvider } from "contracts/interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOrigamiBorrowAndLend } from "contracts/interfaces/common/borrowAndLend/IOrigamiBorrowAndLend.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Migrate a borrow and lend position from and old contract to a new
 * contract, using a flashloan
 * 1/ Flashloan debt token - enough to repay the entire debt
 * 2/ repayAndWithdraw(entire_debt, entire_collateral)
 * 3/ supplyAndBorrow(entire_collateral, entire_debt)
 * 4/ repay flashloan
 * 
 * It's the MULTISIG's responsibility to do this within a single multisig transaction:
 *   a/ Deploy the newBorrowLend
 *   b/ newBorrowLend.setPositionOwner(oldBorrowLend.positionOwner())
 *   c/ GRANT access for this migrator to call oldBorrowLend.repayAndWithdraw()
 *   d/ GRANT access for this migrator to call newBorrowLend.supplyAndBorrow()
 *   e/ Call newBorrowLend.execute()
 *   f/ lovTokenManager.setBorrowLend(newBorrowLend);
 *   g/ REVOKE access for this migrator to call oldBorrowLend.repayAndWithdraw()
 *   h/ REVOKE access for this migrator to call newBorrowLend.supplyAndBorrow()
 */
contract OrigamiBorrowLendMigrator is IOrigamiFlashLoanReceiver, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @notice The Origami flashLoan provider contract, which may be via Aave/Spark/Balancer/etc
    IOrigamiFlashLoanProvider public immutable flashLoanProvider;

    /// @notice The old Origami borrow lend contract
    IOrigamiBorrowAndLend public immutable oldBorrowLend;

    /// @notice The new Origami borrow lend contract
    IOrigamiBorrowAndLend public immutable newBorrowLend;

    /// @notice The collateral token to migrate
    IERC20 public immutable collateralToken;

    /// @notice The debt token to migrate
    IERC20 public immutable debtToken;

    constructor(
        address _initialOwner,
        address _oldBorrowLend,
        address _newBorrowLend,
        address _flashLoanProvider
    ) OrigamiElevatedAccess(_initialOwner) {
        oldBorrowLend = IOrigamiBorrowAndLend(_oldBorrowLend);
        collateralToken = IERC20(oldBorrowLend.supplyToken());
        debtToken = IERC20(oldBorrowLend.borrowToken());

        newBorrowLend = IOrigamiBorrowAndLend(_newBorrowLend);
        flashLoanProvider = IOrigamiFlashLoanProvider(_flashLoanProvider);
    }

    /**
     * @notice only Elevated Access can execute the migration
     */
    function execute() external onlyElevatedAccess {
        // 1. Get the current debt
        uint256 debtAmount = oldBorrowLend.debtBalance();

        // 2. Flashloan that amount
        // When the payment is received, flashLoanCallback() will be called
        flashLoanProvider.flashLoan(
            debtToken,
            debtAmount,
            bytes("")
        );
    }

    /**
     * @notice Handle receiving the flashloan and do the migration
     * The exact amount of flashloan must be repaid to `flashLoanProvider` 
     * at the end of this function
     */
    function flashLoanCallback(
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata /*params*/
    ) external override returns (bool success) {
        if (msg.sender != address(flashLoanProvider)) revert CommonEventsAndErrors.InvalidAccess();
        if (address(token) != address(debtToken)) revert CommonEventsAndErrors.InvalidToken(address(token));
        if (fee > 0) revert CommonEventsAndErrors.InvalidParam();

        // 3. Repay entire debt, withdraw entire collateral and send to the new borrow lend
        debtToken.safeTransfer(address(oldBorrowLend), amount);
        uint256 suppliedCollateral = oldBorrowLend.suppliedBalance();
        (uint256 debtRepaidAmount, uint256 withdrawnAmount) = oldBorrowLend.repayAndWithdraw(
            type(uint256).max, // Use type(uint256).max to ensure it withdraws max shares including any rounding.
            suppliedCollateral, 
            address(newBorrowLend)
        );

        if (debtRepaidAmount != amount) revert CommonEventsAndErrors.InvalidAmount(address(debtToken), debtRepaidAmount);
        if (withdrawnAmount != suppliedCollateral) revert CommonEventsAndErrors.InvalidAmount(address(collateralToken), suppliedCollateral);

        // 4. Supply the collateral to the new borrow lend, and borrow the entire debt amount
        // The debt is sent to the flashLoanProvider for flashloan repayment.
        newBorrowLend.supplyAndBorrow(suppliedCollateral, amount, msg.sender);
        return true;
    }
}
