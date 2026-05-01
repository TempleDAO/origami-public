pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginKyberSwap.sol)

import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin for KyberSwap
/// @dev This can handle scaling balances by a small amount at runtime.
interface IOrigamiBundlerPluginKyberSwap is IOrigamiBundlerPluginMultiAccess {
    error ScalingFailed();

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Swap via KyberSwap
    /// @dev
    ///   - The kyberswap API is used to get the calldata offchain first for an amount of `srcToken`
    ///     See:
    /// https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/aggregator-api-specification/evm-swaps -
    /// Slippage, and skimming of surplus balances of src/dest tokens are left to the caller to check.
    /// @param srcToken Token to sell.
    /// @param callData Swap data to call the router with. Contains routing information.
    function swap(address srcToken, bytes memory callData) external;

    /// @notice Swap via KyberSwap, adjusting the amount to sell to be the current balance of this contract.
    /// @dev
    ///   - The kyberswap API is used to get the calldata offchain first for an amount of `srcToken`,
    ///     which is then modified in order to scale that calldata to the current balance amount.
    ///     See:
    /// https://docs.kyberswap.com/kyberswap-solutions/kyberswap-aggregator/developer-guides/scaling-swap-calldata-with-scalehelper
    /// - The kyberswap API should be called with `onlyScalableSources=true`
    ///   - Slippage, and skimming of surplus balances of src/dest tokens are left to the caller to check.
    /// @param srcToken Token to sell.
    /// @param callData Swap data to call the router with. Contains routing information.
    function swapBalance(address srcToken, bytes memory callData) external;

    /****** VIEWS ******/

    /// @notice The KyberSwap router contract
    function ROUTER() external view returns (address);

    /// @notice A KyberSwap contract to help scale pre-fetched calldata to sell an updated exact amount of tokens
    function SCALING_HELPER() external view returns (address);
}
