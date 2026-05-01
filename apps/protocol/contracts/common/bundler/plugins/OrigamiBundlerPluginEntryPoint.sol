pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginEntryPoint.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IPermit2AllowanceTransfer } from "contracts/interfaces/external/permit2/IPermit2AllowanceTransfer.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";
import { IWrappedToken } from "contracts/interfaces/common/IWrappedToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";

/// @title Origami Bundler - Plugin Entry Point
/// @notice Plugin entry point to pull tokens from initiator
contract OrigamiBundlerPluginEntryPoint is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginEntryPoint {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWrappedToken;
    using SafeCast for uint256;

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    address public immutable override PERMIT2;

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    address public immutable override WRAPPED_NATIVE;

    constructor(address _initialOwner, address _permit2, address _wrappedNative)
        OrigamiBundlerPluginMultiAccess(_initialOwner)
    {
        PERMIT2 = _permit2;
        WRAPPED_NATIVE = _wrappedNative;
    }

    /// @dev Native tokens are received by the adapter and should be either used or wrapped (eg WETH)
    /// before using in other adapters.
    receive() external payable virtual { }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function nativeTransfer(address receiver, uint256 amount) external override withApprovedBundler {
        if (receiver == address(0) || receiver == address(this)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        Address.sendValue(payable(receiver), amount);
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function nativeTransferBalance(address receiver, uint256 minAmount) external override withApprovedBundler {
        if (receiver == address(0) || receiver == address(this)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        uint256 amount = address(this).balance;
        if (amount < minAmount) revert CommonEventsAndErrors.Slippage(minAmount, amount);
        if (amount > 0) {
            Address.sendValue(payable(receiver), amount);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function erc20TransferFromInitiator(address token, address receiver, uint256 amount)
        external
        override
        withApprovedBundler
    {
        address _initiator = initiatorT();
        if (_initiator == address(0)) revert CommonEventsAndErrors.InvalidAddress(_initiator);
        if (receiver == address(0) || receiver == _initiator) revert CommonEventsAndErrors.InvalidAddress(receiver);

        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        IERC20(token).safeTransferFrom(_initiator, receiver, amount);
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function erc20TransferBalanceFromInitiator(address token, address receiver, uint256 minAmount)
        external
        override
        withApprovedBundler
    {
        address _initiator = initiatorT();
        if (_initiator == address(0)) revert CommonEventsAndErrors.InvalidAddress(_initiator);
        if (receiver == address(0) || receiver == _initiator) revert CommonEventsAndErrors.InvalidAddress(receiver);

        uint256 amount = IERC20(token).balanceOf(_initiator);
        if (amount < minAmount) revert CommonEventsAndErrors.Slippage(minAmount, amount);
        if (amount > 0) {
            IERC20(token).safeTransferFrom(_initiator, receiver, amount);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function permit2TransferFromInitiator(address token, address receiver, uint256 amount)
        external
        override
        withApprovedBundler
    {
        address _initiator = initiatorT();
        if (_initiator == address(0)) revert CommonEventsAndErrors.InvalidAddress(_initiator);
        if (receiver == address(0) || receiver == _initiator) revert CommonEventsAndErrors.InvalidAddress(receiver);

        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        IPermit2AllowanceTransfer(PERMIT2).transferFrom(_initiator, receiver, amount.encodeUInt160(), token);
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function permit2TransferBalanceFromInitiator(address token, address receiver, uint256 minAmount)
        external
        override
        withApprovedBundler
    {
        address _initiator = initiatorT();
        if (_initiator == address(0)) revert CommonEventsAndErrors.InvalidAddress(_initiator);
        if (receiver == address(0) || receiver == _initiator) revert CommonEventsAndErrors.InvalidAddress(receiver);

        uint256 amount = IERC20(token).balanceOf(_initiator);
        if (amount < minAmount) revert CommonEventsAndErrors.Slippage(minAmount, amount);
        if (amount > 0) {
            IPermit2AllowanceTransfer(PERMIT2).transferFrom(_initiator, receiver, amount.encodeUInt160(), token);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function wrapNative(uint256 amount, address receiver) external override withApprovedBundler {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _wrapNative(amount, receiver);
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function wrapNativeBalance(address receiver) external override withApprovedBundler {
        uint256 amount = address(this).balance;
        if (amount > 0) {
            _wrapNative(amount, receiver);
        }
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function unwrapNative(uint256 amount, address receiver) external override withApprovedBundler {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _unwrapNative(amount, receiver);
    }

    /// @inheritdoc IOrigamiBundlerPluginEntryPoint
    function unwrapNativeBalance(address receiver) external override withApprovedBundler {
        uint256 amount = IWrappedToken(WRAPPED_NATIVE).balanceOf(address(this));
        if (amount > 0) {
            _unwrapNative(amount, receiver);
        }
    }

    /****** VIEWS ******/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        pure
        virtual
        override(IERC165, OrigamiBundlerPluginMultiAccess)
        returns (bool)
    {
        return OrigamiBundlerPluginMultiAccess.supportsInterface(interfaceId)
            || interfaceId == type(IOrigamiBundlerPluginEntryPoint).interfaceId;
    }

    /****** INTERNALS ******/

    function _wrapNative(uint256 amount, address receiver) private {
        if (receiver == address(0)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        IWrappedToken wNative = IWrappedToken(WRAPPED_NATIVE);
        wNative.deposit{ value: amount }();
        if (receiver != address(this)) {
            wNative.safeTransfer(receiver, amount);
        }
    }

    function _unwrapNative(uint256 amount, address receiver) private {
        if (receiver == address(0)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        IWrappedToken(WRAPPED_NATIVE).withdraw(amount);
        if (receiver != address(this)) {
            Address.sendValue(payable(receiver), amount);
        }
    }
}
