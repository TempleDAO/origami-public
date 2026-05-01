pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Dummy DEX Router
 * @notice A dummy DEX router for testing purposes
 * @dev This router must be pre-funded with any tokens that it will distribute
 */
contract DummyDexRouter {
    using SafeERC20 for IERC20;

    /**
     * @notice A swap that gives the exact requested amount of the buyToken
     */
    function doExactSwap(address sellToken, uint256 sellTokenAmount, address buyToken, uint256 buyTokenAmount) external {
        IERC20(sellToken).safeTransferFrom(msg.sender, address(this), sellTokenAmount);
        IERC20(buyToken).safeTransfer(msg.sender, buyTokenAmount);
    }
}
