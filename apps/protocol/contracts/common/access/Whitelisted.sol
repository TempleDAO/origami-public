pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/access/Whitelisted.sol)

import { IWhitelisted } from "contracts/interfaces/common/access/IWhitelisted.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Whitelisted abstract contract
 * @notice Functionality to deny non-EOA addresses unless whitelisted
 */
abstract contract Whitelisted is IWhitelisted, OrigamiElevatedAccess {
    /**
     * @notice Allow all (both EOAs and contracts) without whitelisting
     */
    bool public override allowAll;

    /**
     * @notice A mapping of whitelisted accounts (not required for EOAs)
     */
    mapping(address account => bool allowed) public override allowedAccounts;

    /**
     * @notice Allow all callers without whitelisting
     */
    function setAllowAll(bool value) external override onlyElevatedAccess {
        allowAll = value;
        emit AllowAllSet(value);
    }

    /**
     * @notice Set whether a given account is allowed or not
     */
    function setAllowAccount(address account, bool value) external override onlyElevatedAccess {
        if (account == address(0)) revert CommonEventsAndErrors.InvalidAddress(account);
        if (account.code.length == 0) revert CommonEventsAndErrors.InvalidAddress(account);

        allowedAccounts[account] = value;
        emit AllowAccountSet(account, value);
    }

    /**
     * @notice Returns false for contracts unless whitelisted, or until allowAll is set to true.
     * @dev This cannot block contracts which deposit within their constructor, but the goal is to minimise 3rd
     * party integrations. This will also deny contract based wallets (eg Gnosis Safe)
     */
    function _isAllowed(address account) internal view returns (bool) {
        if (allowAll) return true;

        // Note: If the account is a contract and access is checked within it's constructor
        // then this will still return true (unavoidable). This is just a deterrant for non-approved integrations, 
        // not intended as full protection.
        if (account.code.length == 0) return true;

        // Contracts need to be explicitly allowed
        return allowedAccounts[account];
    }
}
