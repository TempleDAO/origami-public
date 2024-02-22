pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

contract SafeCastTest is OrigamiTest {
    function test_encodeUInt128_success() public {
        assertEq(
            SafeCast.encodeUInt128(uint256(type(uint128).max)),
            type(uint128).max
        );

        assertEq(
            SafeCast.encodeUInt128(uint256(0)),
            uint128(0)
        );
    }

    function test_encodeUInt128_failure() public {
        uint256 x = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt128(x);
    }
}
