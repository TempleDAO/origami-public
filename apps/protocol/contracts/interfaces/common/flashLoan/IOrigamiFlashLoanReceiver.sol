pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/flashLoan/IOrigamiFlashLoanReceiver.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Handle Flash Loan callback's originated from a `IOrigamiFlashLoanProvider`
 */
interface IOrigamiFlashLoanReceiver {
    /**
     * @notice Invoked from IOrigamiFlashLoanProvider once a flash loan is successfully
     * received, to the msg.sender of `flashLoan()`
     * @dev Must return false (or revert) if handling within the callback failed.
     * @param token The ERC20 token which has been borrowed
     * @param amount The amount which has been borrowed
     * @param fee The flashloan fee amount (in the same token)
     * @param params Client specific abi encoded params which are passed through from the original `flashLoan()` call
     */
    function flashLoanCallback(
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external returns (bool success);
}
