pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

/// @title Origami Bundler - Plugin With Multi-Access suport
/// @notice The same as OrigamiBundlerPluginCore however supports whitelisting multiple bundlers.
contract OrigamiBundlerPluginMultiAccess is
    IOrigamiBundlerPluginMultiAccess,
    OrigamiBundlerPluginCore,
    OrigamiElevatedAccess
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBundlerPluginMultiAccess
    mapping(address account => bool value) public override approvedBundlers;

    constructor(address initialOwner) OrigamiElevatedAccess(initialOwner) { }

    /// @inheritdoc IOrigamiBundlerPluginMultiAccess
    function setBundlerApproved(address account, bool value) public override onlyElevatedAccess {
        // Only require checking the interface on approval. Revoke approval unconditionally.
        if (value && !ERC165Checker.supportsInterface(account, type(IOrigamiBundler).interfaceId)) {
            revert InvalidBundler(account);
        }
        emit BundlerApprovedSet(account, value);
        approvedBundlers[account] = value;
    }

    /// @inheritdoc OrigamiBundlerPluginCore
    function isApprovedBundler(address account)
        public
        view
        override(IOrigamiBundlerPlugin, OrigamiBundlerPluginCore)
        returns (bool)
    {
        return approvedBundlers[account];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginCore)
        returns (bool)
    {
        return OrigamiBundlerPluginCore.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginMultiAccess).interfaceId
            || interfaceId == type(IOrigamiElevatedAccess).interfaceId;
    }
}
