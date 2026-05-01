// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import { Kernel, Policy, Keycode, Permissions, toKeycode } from "contracts/test/external/olympus/src/Kernel.sol";

interface MINTRv1 {
    function VERSION() external view returns (uint8 major, uint8 minor);

    function mintOhm(address to_, uint256 amount_) external;
    function increaseMintApproval(address policy_, uint256 amount_) external;
}

contract MockOhmMinterPolicy is Policy {
    MINTRv1 public MINTR;

    constructor(Kernel _kernel) Policy(_kernel) { }

    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](1);
        dependencies[0] = toKeycode("MINTR");

        MINTR = MINTRv1(getModuleAddress(dependencies[0]));

        (uint8 MINTR_MAJOR, ) = MINTR.VERSION();

        // Ensure Modules are using the expected major version.
        // Modules should be sorted in alphabetical order.
        bytes memory expected = abi.encode([1]);
        if (MINTR_MAJOR != 1) revert Policy_WrongModuleVersion(expected);
    }

    function requestPermissions() external pure override returns (Permissions[] memory requests) {
        Keycode MINTR_KEYCODE = toKeycode("MINTR");

        requests = new Permissions[](2);
        requests[0] = Permissions(MINTR_KEYCODE, MINTRv1.mintOhm.selector);
        requests[1] = Permissions(MINTR_KEYCODE, MINTRv1.increaseMintApproval.selector);
    }

    function mintOhm(address to_, uint256 amount_) external {
        MINTR.increaseMintApproval(address(this), amount_);
        MINTR.mintOhm(to_, amount_);
    }
}
