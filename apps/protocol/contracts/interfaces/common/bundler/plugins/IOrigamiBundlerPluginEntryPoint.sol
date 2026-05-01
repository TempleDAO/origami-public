pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol)

import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin Entry Point
/// @notice Plugin entry point to pull tokens from initiator
interface IOrigamiBundlerPluginEntryPoint is IOrigamiBundlerPluginMultiAccess {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Transfers a fixed amount of native assets to the receiver.
    /// @param receiver The address that will receive the native assets.
    /// @param amount The amount of native assets to transfer, cannot be zero.
    function nativeTransfer(address receiver, uint256 amount) external;

    /// @notice Transfers the current balance of native assets to the receiver.
    /// @param receiver The address that will receive the native assets.
    /// @param minAmount Revert with `Slippage()` if the derived amount of assets to transfer is less than the
    /// minAmount.
    function nativeTransferBalance(address receiver, uint256 minAmount) external;

    /// @notice Pulls a fixed amount of ERC20 tokens from the bundle initiator to receiver via traditional ERC20
    /// approval. @dev `initiator` must have given sufficient allowance to the plugin to spend their tokens.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param amount The amount of token to transfer, cannot be zero.
    function erc20TransferFromInitiator(address token, address receiver, uint256 amount) external;

    /// @notice Pulls the initiator's current balance of ERC20 tokens to receiver via traditional ERC20 approval.
    /// @dev initiator must have given sufficient allowance to the plugin to spend their tokens.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param minAmount Revert with `Slippage()` if the derived amount of tokens to transfer is less than the
    /// minAmount.
    function erc20TransferBalanceFromInitiator(address token, address receiver, uint256 minAmount) external;

    /// @notice Pulls a fixed amount of ERC20 tokens from the bundle initiator to receiver via Permit2.
    /// @dev initiator must have given sufficient allowance to Permit2.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param amount The amount of token to transfer, cannot be zero.
    function permit2TransferFromInitiator(address token, address receiver, uint256 amount) external;

    /// @notice Transfers the initiator's current balance of ERC20 tokens to receiver via Permit2.
    /// @dev initiator must have given sufficient allowance to Permit2.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param minAmount Revert with `Slippage()` if the derived amount of tokens to transfer is less than the
    /// minAmount.
    function permit2TransferBalanceFromInitiator(address token, address receiver, uint256 minAmount) external;

    /// @notice Wraps native tokens to wNative and sends to receiver.
    /// @dev
    ///   - Native tokens must have been previously sent to the adapter.
    ///   - Zero amounts will revert
    /// @param amount The amount of native token to wrap.
    /// @param receiver The account receiving the wrapped native tokens.
    function wrapNative(uint256 amount, address receiver) external;

    /// @notice Wraps the current balance of native tokens to wNative and sends to receiver.
    /// @dev
    ///   - Native tokens must have been previously sent to the adapter.
    ///   - A zero balance will be a no-op
    /// @param receiver The account receiving the wrapped native tokens.
    function wrapNativeBalance(address receiver) external;

    /// @notice Unwraps wNative tokens to the native token and sends to receiver.
    /// @dev
    ///   - Wrapped native tokens must have been previously sent to the adapter.
    ///   - Zero amounts will revert
    /// @param amount The amount of wrapped native token to unwrap.
    /// @param receiver The account receiving the native tokens.
    function unwrapNative(uint256 amount, address receiver) external;

    /// @notice Unwraps the current balance of wNative tokens to the native token and sends to receiver.
    /// @dev
    ///   - Wrapped native tokens must have been previously sent to the adapter.
    ///   - A zero balance will be a no-op
    /// @param receiver The account receiving the native tokens.
    function unwrapNativeBalance(address receiver) external;

    /****** VIEWS ******/

    /// @notice The canonical Permit2 address.
    /// @dev
    ///    [Github](https://github.com/Uniswap/permit2)
    ///    [Etherscan eg](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3)
    function PERMIT2() external view returns (address);

    /// @notice The address of the wrapped native token.
    function WRAPPED_NATIVE() external view returns (address);
}
