// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import { ROLESv1 } from "contracts/test/external/olympus/src/modules/ROLES/ROLES.v1.sol";
import { Kernel, Policy, Keycode, Permissions, toKeycode } from "contracts/test/external/olympus/src/Kernel.sol";

/// @notice The RolesAdmin Policy grants and revokes Roles in the ROLES module.
contract MockRolesAdminPolicy is Policy {
    ROLESv1 public ROLES;

    constructor(Kernel _kernel) Policy(_kernel) { }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("ROLES");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));

        (uint8 ROLES_MAJOR, ) = ROLES.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1]);
        if (ROLES_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        Keycode ROLES_KEYCODE = toKeycode("ROLES");

        requests = new Permissions[](2);
        requests[0] = Permissions(ROLES_KEYCODE, ROLES.saveRole.selector);
        requests[1] = Permissions(ROLES_KEYCODE, ROLES.removeRole.selector);
    }

    function grantRole(bytes32 role_, address wallet_) external {
        ROLES.saveRole(role_, wallet_);
    }

    function revokeRole(bytes32 role_, address wallet_) external {
        ROLES.removeRole(role_, wallet_);
    }
}
