pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsBase.sol)

import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin to join/exit Origami Tokenized Balance Sheet Vaults
/// @dev Vaults need to be whitelisted by admin
interface IOrigamiBundlerPluginTbsBase is IOrigamiBundlerPluginMultiAccess {
    error InvalidVault();
    error NotAsset();
    error NotLiability();

    event TrustedVaultSet(address indexed vault, bool isTrusted);

    /// @notice Set a vault as being trusted
    function trustVault(address vault) external;

    /// @notice Set a vault as NOT being trusted.
    /// @param vault The vault which is no longer trusted.
    /// @param revokeTokenApprovals Whether to revoke all known token approvals for this vault.
    ///        Set to false if the list is too large, and call `revokeApprovals()` in batches
    ///        Note actual allowance may not be revoked if it uses too much gas or reverts.
    /// @param revokeGasStipend If revoking approvals, what is the max gas that can be used per token revocation
    ///        A sensible default might be 50,000 gas. In practice it should generally be much less
    function dontTrustVault(address vault, bool revokeTokenApprovals, uint256 revokeGasStipend) external;

    /// @notice Revoke allowances for a vault to spend tokens held by this contract
    function revokeApprovals(address vault, address[] calldata tokens) external;

    /****** VIEWS ******/

    /// @notice Whether the vault is a trusted Origami vault or not
    function isVaultTrusted(address vault) external view returns (bool);

    /// @notice The set of approved tokens for a given vault. If a vault is not trusted
    /// this will return zero items.
    /// @dev May use more than the block gas limit if too many items
    function getApprovedTokens(address vault) external view returns (address[] memory);
}
