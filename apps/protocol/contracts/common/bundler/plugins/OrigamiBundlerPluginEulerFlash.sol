pragma solidity ^0.8.28;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/bundler/plugins/OrigamiBundlerPluginEulerFlash.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IEVKEVault as IEVault } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { IEulerFlashLoan } from "contracts/interfaces/external/euler/IEulerFlashLoan.sol";

import {
    IOrigamiBundlerPluginEulerFlash
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEulerFlash.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/// @title Origami Bundler - Plugin for Euler Flashloans
contract OrigamiBundlerPluginEulerFlash is OrigamiBundlerPluginMultiAccess, IOrigamiBundlerPluginEulerFlash {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiBundlerPluginEulerFlash
    uint256 public transient override flashloanTotalAmountT;

    /// @dev Transient: The Euler vault which is the source of the flash loan funds
    address private transient vaultT;

    /// @inheritdoc IOrigamiBundlerPluginEulerFlash
    uint256 public constant override flashloanFeeBps = 0;

    constructor(address _initialOwner) OrigamiBundlerPluginMultiAccess(_initialOwner) { }

    /****** BUNDLER PLUGIN ACTIONS ******/

    /// @inheritdoc IOrigamiBundlerPluginEulerFlash
    function flashLoan(address vault, uint256 amount, bytes calldata callbackData)
        external
        override
        withApprovedBundler
    {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        // Utilise transient storage to set the vault and amount
        uint256 _prevTotalAmount = flashloanTotalAmountT;
        address _prevVault = vaultT;
        flashloanTotalAmountT = amount;
        vaultT = vault;

        IEVault(vault).flashLoan(amount, callbackData);

        // Reset the transient storage
        flashloanTotalAmountT = _prevTotalAmount;
        vaultT = _prevVault;
    }

    /****** EULER CALLBACKS ******/

    /// @inheritdoc IEulerFlashLoan
    function onFlashLoan(bytes calldata callbackData) external override {
        // The msg.sender is expected to be the EVault set from transient storage in flashLoan().
        IEVault vault = IEVault(vaultT);
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAddress(msg.sender);

        uint256 requiredToRepay = flashloanTotalAmountT;
        IERC20 flashToken = IERC20(vault.asset());
        _reenterBundle(callbackData);

        if (flashToken.balanceOf(address(this)) < requiredToRepay) {
            revert CommonEventsAndErrors.InsufficientBalance(
                address(flashToken), requiredToRepay, flashToken.balanceOf(address(this))
            );
        }

        flashToken.safeTransfer(msg.sender, requiredToRepay);
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
            || interfaceId == type(IOrigamiBundlerPluginEulerFlash).interfaceId;
    }
}
