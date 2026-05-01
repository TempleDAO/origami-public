pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title Origami Bundler - Plugin Interface
/// @notice Common plugin actions and helpers to use with OrigamiBundler
interface IOrigamiBundlerPlugin is IERC165 {
    error InvalidBundler(address account);

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Transfers a fixed amount of ERC20 tokens to a receiver.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param amount The amount of token to transfer, cannot be zero.
    function erc20Transfer(address token, address receiver, uint256 amount) external;

    /// @notice Transfers the current balance of ERC20 tokens to a receiver.
    /// @dev Zero amounts are allowed and will just be a no-op.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param minAmount Revert with `Slippage()` if the derived amount of tokens to transfer is less than the
    /// minAmount.
    function erc20TransferBalance(address token, address receiver, uint256 minAmount) external;

    /****** VIEWS ******/

    /// @notice Whether a contract is an approved bundler for this plugin. It is up to the implementation to decide
    /// if that is a single contract, or if it can be reused across multiple bundler contracts.
    /// @dev To simplify the security model, all bundler plugin actions should be gated with the `withApprovedBundler`
    /// modifier.
    function isApprovedBundler(address account) external view returns (bool);

    /// @notice Returns the current bundler() stored in the plugin context.
    /// @dev This is transient storage - it is only set within the context of the `withApprovedBundler` modifier
    /// The bundler value being non-zero indicates that a bundle is being processed.
    function bundler() external view returns (address);
}
