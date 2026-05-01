pragma solidity ^0.8.28;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginCore.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { LibCall } from "solady/utils/LibCall.sol";

import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";

/// @title Origami Bundler - Plugin Core
/// @notice Common plugin actions and helpers to use with OrigamiBundler
abstract contract OrigamiBundlerPluginCore is IOrigamiBundlerPlugin {
    using SafeERC20 for IERC20;

    /// @dev The appproved bundler is set as transient storage context on the outer most call
    address private transient _bundlerT;

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPlugin
    function erc20Transfer(address token, address receiver, uint256 amount) external override withApprovedBundler {
        if (receiver == address(0) || receiver == address(this)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        IERC20(token).safeTransfer(receiver, amount);
    }

    /// @inheritdoc IOrigamiBundlerPlugin
    function erc20TransferBalance(address token, address receiver, uint256 minAmount)
        external
        override
        withApprovedBundler
    {
        if (receiver == address(0) || receiver == address(this)) {
            revert CommonEventsAndErrors.InvalidAddress(receiver);
        }
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < minAmount) revert CommonEventsAndErrors.Slippage(minAmount, amount);
        if (amount > 0) {
            IERC20(token).safeTransfer(receiver, amount);
        }
    }

    /****** VIEWS ******/

    /// @inheritdoc IOrigamiBundlerPlugin
    function bundler() public view override returns (address) {
        return _bundlerT;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IOrigamiBundlerPlugin).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @dev Is the provided account an approved 'bundler' in order to call `withApprovedBundler` plugin functions
    function isApprovedBundler(address account) public view virtual returns (bool);

    /// @dev Returns the current initiator stored in the adapter.
    /// The initiator value being non-zero indicates that a bundle is being processed.
    function initiatorT() internal view returns (address) {
        address __bundler = _bundlerT;
        return __bundler == address(0) ? address(0) : IOrigamiBundler(__bundler).initiatorT();
    }

    /// @dev Ensure the msg.sender is an approved bundler, and set the `_bundlerT` transient storage for the duration
    /// of the call stack - including any reentry.
    // `_bundlerT` is used for any required reentry.
    // forge-lint: disable-next-item(unwrapped-modifier-logic)
    modifier withApprovedBundler() virtual {
        // NB: Functions are to gas golf contract byte size.
        bool resetBundler = _withApprovedBundler(msg.sender);
        _;
        _resetBundler(resetBundler);
    }

    function _withApprovedBundler(address caller) internal returns (bool setBundler) {
        address _existingBundler = _bundlerT;
        if (_existingBundler == address(0)) {
            // If the bundler has not yet been set in this scope then check it's valid
            // and set before executing the function.
            if (!isApprovedBundler(caller)) revert InvalidBundler(caller);

            _bundlerT = caller;

            // Ensure to unset _bundlerT again after execution.
            return true;
        } else if (_existingBundler == caller) {
            // Already set - just execute the underlying function
            return false;
        } else {
            // Dont allow mixing of bundlers within the same scope.
            // Eg a plugin call reenters and the call chain executes the same plugin function
            // via a different bundler.
            revert InvalidBundler(caller);
        }
    }

    function _resetBundler(bool doReset) internal {
        if (doReset) _bundlerT = address(0);
    }

    /// @notice Calls bundler.reenter with an already encoded Call array.
    /// @param data An abi-encoded IOrigamiBundler.Call[].
    function _reenterBundle(bytes calldata data) internal {
        // This also ensures _bundlerT is non-zero
        LibCall.callContract(_bundlerT, bytes.concat(IOrigamiBundler.reenter.selector, data));
    }
}
