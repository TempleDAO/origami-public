pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";

/* solhint-disable func-name-mixedcase */
contract DummyElevatedAccess is OrigamiElevatedAccess {
    constructor(
        address _initialOwner
    ) OrigamiElevatedAccess(_initialOwner)
    // solhint-disable-next-line no-empty-blocks
    {}

    // solhint-disable-next-line no-empty-blocks
    function validateOnlyElevatedAccess() public view onlyElevatedAccess {}

    function checkSig() public view {
        validateOnlyElevatedAccess();
    }

    function checkSigThis() public view {
        this.validateOnlyElevatedAccess();
    }

    // A magic function with a signature of 0x00000000
    function wycpnbqcyf() external view onlyElevatedAccess {}
}

