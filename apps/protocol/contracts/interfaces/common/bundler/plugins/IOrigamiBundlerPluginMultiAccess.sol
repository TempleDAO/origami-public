pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol)

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

/// @title Origami Bundler - Plugin with Whitelisted callers
/// @notice Common calls and helpers to use with OrigamiBundler
interface IOrigamiBundlerPluginMultiAccess is IOrigamiBundlerPlugin, IOrigamiElevatedAccess {
    event BundlerApprovedSet(address account, bool value);

    /// @notice Set whether an account is an approved bundler in order to call plugin functions.
    function setBundlerApproved(address account, bool value) external;

    /// @notice If an account is whitelisted as an approved bundler which can call plugin functions.
    function approvedBundlers(address account) external view returns (bool);
}
