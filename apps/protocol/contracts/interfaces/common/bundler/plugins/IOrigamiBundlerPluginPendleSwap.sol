pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginPendleSwap.sol)

import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin for swapping assets on Pendle
/// @dev This can handle scaling balances by a small amount at runtime.
interface IOrigamiBundlerPluginPendleSwap is IOrigamiBundlerPluginMultiAccess {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Swap via Pendle Router
    /// @dev
    ///   - The Pendle API v2 /convert endpoint is used to get the calldata offchain first for an amount of `srcToken`
    ///     See: https://api-v2.pendle.finance/core/docs#/SDK/SdkController_convert
    ///   - Slippage, and skimming of surplus balances of src/dest tokens are left to the caller to check.
    /// @param srcToken Token to sell.
    /// @param callData Swap data to call the router with. Contains routing information.
    function swap(address srcToken, bytes memory callData) external;

    /// @notice Swap via Pendle Router, adjusting the amount to sell to be the current balance of this contract.
    /// @dev
    ///   - The Pendle API v2 /convert is used to get the calldata offchain first for an amount of `srcToken`,
    ///     which is then modified in order to scale that calldata to the current balance amount.
    ///     See: https://api-v2.pendle.finance/core/docs#/SDK/SdkController_convert
    ///   - The Pendle should be called with `needScale=true`
    ///   - Slippage, and skimming of surplus balances of src/dest tokens are left to the caller to check.
    ///   - Will revert with UnsupportedSelector() if not supported.
    /// @param srcToken Token to sell.
    /// @param callData Swap data to call the router with. Contains routing information.
    function swapBalance(address srcToken, bytes memory callData) external;

    /****** VIEWS ******/

    /// @notice The Pendle router contract
    function ROUTER() external view returns (address);

    /// @notice Within the Pendle router calldata, scale to the updated sell amount:
    ///  - The token sell amount
    ///  - The min buy amount
    /// @dev Will revert with UnsupportedSelector() if not supported.
    function scaleCalldata(uint256 newSrcAmount, bytes calldata callData)
        external
        view
        returns (bytes memory scaledCallData);
}
