// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ROLESv1} from "../../modules/ROLES/ROLES.v1.sol";
import {RolesConsumer} from "../../modules/ROLES/OlympusRoles.sol";
import {ADMIN_ROLE, EMERGENCY_ROLE} from "./RoleDefinitions.sol";

abstract contract PolicyAdmin is RolesConsumer {
    error NotAuthorised();

    /// @notice Modifier that reverts if the caller does not have the emergency or admin role
    modifier onlyEmergencyOrAdminRole() {
        if (!_isEmergency(msg.sender) && !_isAdmin(msg.sender)) revert NotAuthorised();
        _;
    }

    /// @notice Modifier that reverts if the caller does not have the admin role
    modifier onlyAdminRole() {
        if (!_isAdmin(msg.sender)) revert ROLESv1.ROLES_RequireRole(ADMIN_ROLE);
        _;
    }

    /// @notice Modifier that reverts if the caller does not have the emergency role
    modifier onlyEmergencyRole() {
        if (!_isEmergency(msg.sender)) revert ROLESv1.ROLES_RequireRole(EMERGENCY_ROLE);
        _;
    }

    /// @notice Check if an account has the admin role
    ///
    /// @param  account_ The account to check
    /// @return true if the account has the admin role, false otherwise
    function _isAdmin(address account_) internal view returns (bool) {
        return ROLES.hasRole(account_, ADMIN_ROLE);
    }

    /// @notice Check if an account has the emergency role
    ///
    /// @param  account_ The account to check
    /// @return true if the account has the emergency role, false otherwise
    function _isEmergency(address account_) internal view returns (bool) {
        return ROLES.hasRole(account_, EMERGENCY_ROLE);
    }
}
