pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { Range } from "contracts/libraries/Range.sol";

contract RangeTest is OrigamiTest {
    using Range for Range.Data;

    Range.Data public range;

    function setUp() public {
        range = Range.Data({
            floor: 1e18,
            ceiling: 100e18
        });
    }

    function test_set_failure() public {
        assertEq(range.floor, 1e18);
        assertEq(range.ceiling, 100e18);

        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 60e18, 50e18));
        range.set(60e18, 50e18);       
    }

    function test_set_success() public {
        assertEq(range.floor, 1e18);
        assertEq(range.ceiling, 100e18);

        range.set(50e18, 60e18);

        assertEq(range.floor, 50e18);
        assertEq(range.ceiling, 60e18);
    }
}
