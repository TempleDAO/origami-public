pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsV1.sol)

import {
    IOrigamiBundlerPluginTbsBase
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsBase.sol";

/// @title Origami Bundler - Plugin to join/exit Origami Tokenized Balance Sheet Vaults (v1 eg hOHM)
/// @dev Vaults need to be whitelisted, and do not support the tokensHash parameter to join/exit.
interface IOrigamiBundlerPluginTbsV1 is IOrigamiBundlerPluginTbsBase {
    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @notice Join a trusted TBS vault using all available balance of `assetAddress`
    /// @dev Enough of all proportional assets must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param assetAddress The address of the asset token to join with, using the current
    ///                     balance of that token in this contract
    /// @param receiver The address that will receive the vault shares and liabilities
    function joinWithAssetBalance(address vaultAddress, address assetAddress, address receiver) external;

    /// @notice Join a trusted TBS vault for an exact amount of tokenAddress (may be an asset or liability)
    /// @dev Enough of all proportional assets must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param tokenAddress The address of the asset/liability token to join with
    /// @param tokenAmount The amount of `tokenAddress` to join with
    /// @param receiver The address that will receive the vault shares and liabilities
    function joinWithToken(address vaultAddress, address tokenAddress, uint256 tokenAmount, address receiver) external;

    /// @notice Join a trusted TBS vault for an exact amount of shares
    /// @dev Enough of all proportional assets must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param shares The amount of shares to be minted
    /// @param receiver The address that will receive the vault shares and liabilities
    function joinWithShares(address vaultAddress, uint256 shares, address receiver) external;

    /// @notice Exit a trusted TBS vault using all available balance of `liabilityAddress`
    /// @dev Enough of all proportional shares and liabilities must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param liabilityAddress The address of the liability token to exit with, using the current
    ///                         balance of that token in this contract
    /// @param receiver The address that will receive the assets
    function exitWithLiabilityBalance(address vaultAddress, address liabilityAddress, address receiver) external;

    /// @notice Exit a trusted TBS vault using an exact amount of tokenAddress (may be an asset or liability)
    /// @dev Enough of all proportional shares and liabilities must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param tokenAddress The address of the asset/liability token to exit with
    /// @param tokenAmount The amount of `tokenAddress` to exit with
    /// @param receiver The address that will receive the assets
    function exitWithToken(address vaultAddress, address tokenAddress, uint256 tokenAmount, address receiver) external;

    /// @notice Exit a trusted TBS vault using all available balance of shares
    /// @dev Enough of all liabilities must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param receiver The address that will receive the assets
    function exitWithSharesBalance(address vaultAddress, address receiver) external;

    /// @notice Exit a trusted TBS vault using an exact amount of shares
    /// @dev Enough of all liabilities must be present in this contract
    /// @param vaultAddress The address of the trusted TBS (v1) vault
    /// @param shares The amount of shares to exit with
    /// @param receiver The address that will receive the assets
    function exitWithShares(address vaultAddress, uint256 shares, address receiver) external;
}
