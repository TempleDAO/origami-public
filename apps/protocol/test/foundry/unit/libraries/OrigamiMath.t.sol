pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiMathTest is OrigamiTest {
    using OrigamiMath for uint256;

    function test_scaleUp() public {
        assertEq(OrigamiMath.scaleUp(123.123450e6, 1e12), 123.123450e18);
        assertEq(OrigamiMath.scaleUp(123.123454e6, 1e12), 123.123454e18);
        assertEq(OrigamiMath.scaleUp(123.123455e6, 1e12), 123.123455e18);
        assertEq(OrigamiMath.scaleUp(123.123456e6, 1e12), 123.123456e18);

        assertEq(OrigamiMath.scaleUp(123.1234560e18, 1), 123.1234560e18);
        assertEq(OrigamiMath.scaleUp(123.1234564e18, 1), 123.1234564e18);
        assertEq(OrigamiMath.scaleUp(123.1234565e18, 1), 123.1234565e18);
        assertEq(OrigamiMath.scaleUp(123.1234566e18, 1), 123.1234566e18);
    }
    function test_scaleDown() public {
        assertEq(uint256(10) ** (18 - 18), 1);

        assertEq(OrigamiMath.scaleDown(123.1234560e18, 1e12, OrigamiMath.Rounding.ROUND_DOWN), 123.123456e6);
        assertEq(OrigamiMath.scaleDown(123.1234564e18, 1e12, OrigamiMath.Rounding.ROUND_DOWN), 123.123456e6);
        assertEq(OrigamiMath.scaleDown(123.1234565e18, 1e12, OrigamiMath.Rounding.ROUND_DOWN), 123.123456e6);
        assertEq(OrigamiMath.scaleDown(123.1234566e18, 1e12, OrigamiMath.Rounding.ROUND_DOWN), 123.123456e6);

        assertEq(OrigamiMath.scaleDown(123.1234560e18, 1e12, OrigamiMath.Rounding.ROUND_UP), 123.123456e6);
        assertEq(OrigamiMath.scaleDown(123.1234564e18, 1e12, OrigamiMath.Rounding.ROUND_UP), 123.123457e6);
        assertEq(OrigamiMath.scaleDown(123.1234565e18, 1e12, OrigamiMath.Rounding.ROUND_UP), 123.123457e6);
        assertEq(OrigamiMath.scaleDown(123.1234566e18, 1e12, OrigamiMath.Rounding.ROUND_UP), 123.123457e6);

        assertEq(OrigamiMath.scaleDown(123.1234560e18, 1, OrigamiMath.Rounding.ROUND_DOWN), 123.1234560e18);
        assertEq(OrigamiMath.scaleDown(123.1234564e18, 1, OrigamiMath.Rounding.ROUND_DOWN), 123.1234564e18);
        assertEq(OrigamiMath.scaleDown(123.1234565e18, 1, OrigamiMath.Rounding.ROUND_DOWN), 123.1234565e18);
        assertEq(OrigamiMath.scaleDown(123.1234566e18, 1, OrigamiMath.Rounding.ROUND_DOWN), 123.1234566e18);

        assertEq(OrigamiMath.scaleDown(123.1234560e18, 1, OrigamiMath.Rounding.ROUND_UP), 123.1234560e18);
        assertEq(OrigamiMath.scaleDown(123.1234564e18, 1, OrigamiMath.Rounding.ROUND_UP), 123.1234564e18);
        assertEq(OrigamiMath.scaleDown(123.1234565e18, 1, OrigamiMath.Rounding.ROUND_UP), 123.1234565e18);
        assertEq(OrigamiMath.scaleDown(123.1234566e18, 1, OrigamiMath.Rounding.ROUND_UP), 123.1234566e18);
    }

    function test_mulDiv() public {
        assertEq(OrigamiMath.mulDiv(123.456789123456789e18, 3.123e18, 4.4567e18, OrigamiMath.Rounding.ROUND_DOWN), 86.511443990521137174e18);
        assertEq(OrigamiMath.mulDiv(123.456789123456789e18, 3.123e18, 4.4567e18, OrigamiMath.Rounding.ROUND_UP), 86.511443990521137175e18);
    }

    function test_subtractBps_zero() public {
        // 0%
        assertEq(OrigamiMath.addBps(100e18, 0), 100e18);

        // 10%
        assertEq(OrigamiMath.addBps(100e18, 1_000), 110e18);

        // 33.333%
        assertEq(OrigamiMath.addBps(100e18, 3_333), 133.33e18);

        // 100%
        assertEq(OrigamiMath.addBps(100e18, 10_000), 200e18);

        // 110%
        assertEq(OrigamiMath.addBps(100e18, 11_000), 210e18);
    }

    function test_subtractBps_success() public {
        // 0%
        assertEq(OrigamiMath.subtractBps(100e18, 0), 100e18);
        
        // 10%
        assertEq(OrigamiMath.subtractBps(100e18, 1_000), 90e18);

        // 33.333%
        assertEq(OrigamiMath.subtractBps(100e18, 3_333), 66.67e18);

        // 100%
        assertEq(OrigamiMath.subtractBps(100e18, 10_000), 0);

        // 110%
        assertEq(OrigamiMath.subtractBps(100e18, 11_000), 0);
    }

    function test_splitSubtractBps_success() public {
        uint256 rate = 3_330; // 33.3%

        uint256 amount = 600;
        (uint256 result, uint256 removed) = amount.splitSubtractBps(rate);
        assertEq(result, 400);
        assertEq(removed, 200);

        amount = 601;
        (result, removed) = amount.splitSubtractBps(rate);
        assertEq(result, 400);
        assertEq(removed, 201);
    }

    function test_inverseSubtractBps_fail() public {
        uint256 amount = 600;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        amount.inverseSubtractBps(10_000 + 1);
    }

    function test_inverseSubtractBps_success() public {
        uint256 rate = 3_330; // 33.3%

        uint256 amount = 400;       
        uint256 result = amount.inverseSubtractBps(rate);
        assertEq(result, 600);

        // And back the other way
        (uint256 result2, uint256 removed) = result.splitSubtractBps(rate);
        assertEq(result2, amount);
        assertEq(removed, 200);

        assertEq(amount.inverseSubtractBps(0), amount);
    }
}
