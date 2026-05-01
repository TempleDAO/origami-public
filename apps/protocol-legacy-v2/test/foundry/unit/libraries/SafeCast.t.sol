pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";

contract SafeCastTest is OrigamiTest {
    function test_encodeUInt128_success() public pure {
        assertEq(
            SafeCast.encodeUInt128(uint256(type(uint128).max)),
            type(uint128).max
        );

        assertEq(
            SafeCast.encodeUInt128(uint256(0)),
            uint128(0)
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_encodeUInt128_failure() public {
        uint256 x = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt128(x);
    }

    function test_encodeUInt112_success() public pure {
        assertEq(
            SafeCast.encodeUInt112(uint256(type(uint112).max)),
            type(uint112).max
        );

        assertEq(
            SafeCast.encodeUInt112(uint256(0)),
            uint112(0)
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_encodeUInt112_failure() public {
        uint256 x = uint256(type(uint112).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeUInt112(x);
    }

    function test_encodeInt256_success() public pure {
        assertEq(
            SafeCast.encodeInt256(uint256(type(int256).max)),
            type(int256).max
        );

        assertEq(
            SafeCast.encodeInt256(uint256(0)),
            int256(0)
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_encodeInt256_failure() public {
        uint256 x = uint256(type(int256).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(SafeCast.Overflow.selector, x));
        SafeCast.encodeInt256(x);
    }
}
