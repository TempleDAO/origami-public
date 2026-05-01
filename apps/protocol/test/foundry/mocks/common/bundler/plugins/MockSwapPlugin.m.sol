pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";

contract MockSwapPlugin is OrigamiBundlerPluginCore {
    using SafeERC20 for IERC20;

    address public immutable approvedBundler;

    constructor(address approvedBundler_) {
        approvedBundler = approvedBundler_;
    }

    function isApprovedBundler(address account) public view override returns (bool) {
        return account == approvedBundler;
    }

    // Simply swaps the requested amounts
    // The funds must have already been sent to this contract
    function swap(
        address,
        /*fromToken*/
        uint256,
        /*fromAmount*/
        address toToken,
        uint256 toAmount,
        address receiver
    )
        external
        withApprovedBundler
    {
        IERC20(toToken).safeTransfer(receiver, toAmount);
    }
}
