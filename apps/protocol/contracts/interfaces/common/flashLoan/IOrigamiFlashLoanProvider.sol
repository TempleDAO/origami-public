pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/flashLoan/IOrigamiFlashLoanProvider.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice An Origami abstraction over FlashLoan providers
 */
interface IOrigamiFlashLoanProvider {
    /**
     * @notice Initiate a flashloan for a single token
     * The caller must implement the `IOrigamiFlashLoanReceiver()` interface.
     * @param token The ERC20 token to borrow
     * @param amount The amount to borrow
     * @param params Client specific abi encoded params which are passed through from the msg.sender 
     *               and into the `flashLoanCallback()` call
     */
    function flashLoan(
        IERC20 token, 
        uint256 amount, 
        bytes memory params
    ) external;
}
