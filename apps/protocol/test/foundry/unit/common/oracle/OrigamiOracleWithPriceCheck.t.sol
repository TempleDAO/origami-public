pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiOracleWithPriceCheck } from "contracts/common/oracle/OrigamiOracleWithPriceCheck.sol";
import { OrigamiFixedPriceOracle } from "contracts/common/oracle/OrigamiFixedPriceOracle.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiOracleWithPriceCheckTestBase is OrigamiTest {

    OrigamiFixedPriceOracle internal oUnderlyingOracle1;
    OrigamiOracleWithPriceCheck internal oOracle1;

    address internal token1 = makeAddr("token1");
    address internal token2 = makeAddr("token2");

    function setUp() public {
        vm.warp(1672531200); // 1 Jan 2023
        vm.startPrank(origamiMultisig);

        // 18 decimals for baseAsset and quoteAsset
        oUnderlyingOracle1 = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/TOKEN2",
                token1,
                18,
                token2,
                6
            ),
            0.99e18,
            address(0)
        );

        // 18 decimals for baseAsset and quoteAsset
        oOracle1 = new OrigamiOracleWithPriceCheck(
            origamiMultisig,
            address(oUnderlyingOracle1),
            Range.Data(0.95e18, 1.05e18)
        );

        vm.stopPrank();
    }
}

contract OrigamiOracleWithPriceCheckTestAdmin is OrigamiOracleWithPriceCheckTestBase {
    event ValidPriceRangeSet(uint128 validFloor, uint128 validCeiling);

    function test_initialization() public view {
        assertEq(oOracle1.baseAsset(), token1);
        assertEq(oOracle1.quoteAsset(), token2);
        assertEq(oOracle1.decimals(), 18);
        assertEq(oOracle1.precision(), 1e18);
        assertEq(oOracle1.assetScalingFactor(), 1e30); // 18 + 12
        assertEq(oOracle1.description(), "TOKEN1/TOKEN2");

        assertEq(address(oOracle1.underlyingOracle()), address(oUnderlyingOracle1));
        (uint128 floor, uint128 ceiling) = oOracle1.validPriceRange();
        assertEq(floor, 0.95e18);
        assertEq(ceiling, 1.05e18);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_access_setValidPriceRange() public {
        expectElevatedAccess();
        oOracle1.setValidPriceRange(1, 2);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_setValidPriceRange_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 5, 4));
        oOracle1.setValidPriceRange(5, 4);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_setValidPriceRange_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(oOracle1));
        emit ValidPriceRangeSet(1e18, 2e18);
        oOracle1.setValidPriceRange(1e18, 2e18);
        
        (uint128 floor, uint128 ceiling) = oOracle1.validPriceRange();
        assertEq(floor, 1e18);
        assertEq(ceiling, 2e18);
    }
}

contract OrigamiOracleWithPriceCheckTestLatestPrice is OrigamiOracleWithPriceCheckTestBase {
    function test_latestPrice_inRange() public view {
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            0.99e18
        );
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            0.99e18
        );

        (
            uint256 price1, 
            uint256 price2, 
            address oracleBaseAsset,
            address oracleQuoteAsset
        ) = oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN,
            IOrigamiOracle.PriceType.HISTORIC_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );
        assertEq(price1, 0.99e18);
        assertEq(price2, 0.99e18);
        assertEq(oracleBaseAsset, token1);
        assertEq(oracleQuoteAsset, token2);
    }

    function test_latestPrice_belowRange() public {
        vm.mockCall(
            address(oUnderlyingOracle1),
            abi.encodeWithSelector(IOrigamiOracle.latestPrice.selector),
            abi.encode(0.8e18)
        );
        
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oUnderlyingOracle1), 
            0.8e18,
            0.95e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
        
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oUnderlyingOracle1), 
            0.8e18,
            0.95e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oUnderlyingOracle1), 
            0.8e18,
            0.95e18
        ));
        oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN,
            IOrigamiOracle.PriceType.HISTORIC_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function test_latestPrice_aboveRange() public {
        vm.mockCall(
            address(oUnderlyingOracle1),
            abi.encodeWithSelector(IOrigamiOracle.latestPrice.selector),
            abi.encode(1.8e18)
        );
        
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oUnderlyingOracle1), 
            1.8e18,
            1.05e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
        
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oUnderlyingOracle1), 
            1.8e18,
            1.05e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oUnderlyingOracle1), 
            1.8e18,
            1.05e18
        ));
        oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN,
            IOrigamiOracle.PriceType.HISTORIC_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );
    }

    function test_matchAssets() public view {
        assertTrue(oOracle1.matchAssets(token1, token2));
        assertTrue(oOracle1.matchAssets(token2, token1));
        assertFalse(oOracle1.matchAssets(token1, alice));
        assertFalse(oOracle1.matchAssets(alice, token2));
    }

    function test_convertAmount_inRange() public {
        assertEq(
            oOracle1.convertAmount(token1, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            99e6
        );
        assertEq(
            oOracle1.convertAmount(token2, 100e6, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            101.010101010101010101e18
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(alice)));
        oOracle1.convertAmount(alice, 100e6, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_convertAmount_zeroPrice() public {
        vm.prank(origamiMultisig);
        oOracle1.setValidPriceRange(0, 100e18);
        vm.mockCall(
            address(oUnderlyingOracle1),
            abi.encodeWithSelector(IOrigamiOracle.latestPrice.selector),
            abi.encode(0)
        );
        assertEq(
            oOracle1.convertAmount(token1, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            0
        );

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oOracle1), 
            0
        ));
        oOracle1.convertAmount(token2, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_convertAmount_belowRange() public {
        vm.mockCall(
            address(oUnderlyingOracle1),
            abi.encodeWithSelector(IOrigamiOracle.latestPrice.selector),
            abi.encode(0.8e18)
        );

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oUnderlyingOracle1), 
            0.8e18,
            0.95e18
        ));
        oOracle1.convertAmount(token1, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oUnderlyingOracle1), 
            0.8e18,
            0.95e18
        ));
        oOracle1.convertAmount(token2, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_convertAmount_aboveRange() public {
        vm.mockCall(
            address(oUnderlyingOracle1),
            abi.encodeWithSelector(IOrigamiOracle.latestPrice.selector),
            abi.encode(1.8e18)
        );
        
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oUnderlyingOracle1), 
            1.8e18,
            1.05e18
        ));
        oOracle1.convertAmount(token1, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oUnderlyingOracle1), 
            1.8e18,
            1.05e18
        ));
        oOracle1.convertAmount(token2, 100e18, IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }
}
