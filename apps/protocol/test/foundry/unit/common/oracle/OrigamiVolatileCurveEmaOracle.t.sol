pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiVolatileCurveEmaOracle } from "contracts/common/oracle/OrigamiVolatileCurveEmaOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ICurveStableSwapNG } from "contracts/interfaces/external/curve/ICurveStableSwapNG.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiVolatileCurveEmaOracleTestBase is OrigamiTest {
    OrigamiVolatileCurveEmaOracle public oOracleReciprocal;
    OrigamiVolatileCurveEmaOracle public oOracleNotReciprocal;

    IERC20Metadata public constant USD0_TOKEN = IERC20Metadata(0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5);
    IERC20Metadata public constant USD0PP_TOKEN = IERC20Metadata(0x35D8949372D46B7a3D5A56006AE77B215fc69bC0);

    ICurveStableSwapNG public constant STABLE_SWAP_NG = ICurveStableSwapNG(0x1d08E7adC263CfC70b1BaBe6dC5Bb339c16Eec52);

    function setUp() public {
        fork("mainnet", 20308622);
        vm.warp(1721006984);

        oOracleReciprocal = new OrigamiVolatileCurveEmaOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USD0/USD0++",
                address(USD0_TOKEN),
                USD0_TOKEN.decimals(),
                address(USD0PP_TOKEN),
                USD0PP_TOKEN.decimals()
            ),
            address(STABLE_SWAP_NG),
            Range.Data(0.99e18, 1.01e18)
        );

        oOracleNotReciprocal = new OrigamiVolatileCurveEmaOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USD0++/USD0",
                address(USD0PP_TOKEN),
                USD0PP_TOKEN.decimals(),
                address(USD0_TOKEN),
                USD0_TOKEN.decimals()
            ),
            address(STABLE_SWAP_NG),
            Range.Data(0.99e18, 1.01e18)
        );
    }
}

contract OrigamiVolatileCurveEmaOracleTestInit is OrigamiVolatileCurveEmaOracleTestBase {
    function test_initialization_reciprocal() public {
        assertEq(oOracleReciprocal.decimals(), 18);
        assertEq(oOracleReciprocal.precision(), 1e18);
        assertEq(oOracleReciprocal.description(), "USD0/USD0++");
        assertEq(oOracleReciprocal.assetScalingFactor(), 1e18);
        assertEq(oOracleReciprocal.baseAsset(), address(USD0_TOKEN));
        assertEq(oOracleReciprocal.quoteAsset(), address(USD0PP_TOKEN));

        assertEq(address(oOracleReciprocal.stableSwapNg()), address(STABLE_SWAP_NG));
        assertEq(oOracleReciprocal.reciprocal(), true);

        (uint128 floor, uint128 ceiling) = oOracleReciprocal.validSpotPriceRange();
        assertEq(floor, 0.99e18);
        assertEq(ceiling, 1.01e18);
    }

    function test_initialization_notReciprocal() public {
        assertEq(oOracleNotReciprocal.decimals(), 18);
        assertEq(oOracleNotReciprocal.precision(), 1e18);
        assertEq(oOracleNotReciprocal.description(), "USD0++/USD0");
        assertEq(oOracleNotReciprocal.assetScalingFactor(), 1e18);
        assertEq(oOracleNotReciprocal.baseAsset(), address(USD0PP_TOKEN));
        assertEq(oOracleNotReciprocal.quoteAsset(), address(USD0_TOKEN));

        assertEq(address(oOracleNotReciprocal.stableSwapNg()), address(STABLE_SWAP_NG));
        assertEq(oOracleNotReciprocal.reciprocal(), false);

        (uint128 floor, uint128 ceiling) = oOracleNotReciprocal.validSpotPriceRange();
        assertEq(floor, 0.99e18);
        assertEq(ceiling, 1.01e18);
    }

    function test_constructor_fail_ncoins() public {
        vm.mockCall(
            address(STABLE_SWAP_NG),
            abi.encodeWithSelector(ICurveStableSwapNG.N_COINS.selector),
            abi.encode(3)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        oOracleReciprocal = new OrigamiVolatileCurveEmaOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USD0/USD0++",
                address(USD0_TOKEN),
                18,
                address(USD0PP_TOKEN),
                18
            ),
            address(STABLE_SWAP_NG),
            Range.Data(0.99e18, 1.01e18)
        );
    }

    function test_constructor_fail_notMatching() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        oOracleReciprocal = new OrigamiVolatileCurveEmaOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USD0/USD0++",
                alice,
                18,
                address(USD0PP_TOKEN),
                18
            ),
            address(STABLE_SWAP_NG),
            Range.Data(0.99e18, 1.01e18)
        );
    }
}

contract OrigamiVolatileCurveEmaOracleTestAdmin is OrigamiVolatileCurveEmaOracleTestBase {
    event ValidPriceRangeSet(uint128 validFloor, uint128 validCeiling);

    function test_setValidSpotPriceRange_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 5, 4));
        oOracleReciprocal.setValidSpotPriceRange(5, 4);
    }

    function test_setValidSpotPriceRange_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(oOracleReciprocal));
        emit ValidPriceRangeSet(1e18, 2e18);
        oOracleReciprocal.setValidSpotPriceRange(1e18, 2e18);
        
        (uint128 floor, uint128 ceiling) = oOracleReciprocal.validSpotPriceRange();
        assertEq(floor, 1e18);
        assertEq(ceiling, 2e18);
    }
}

contract OrigamiVolatileCurveEmaOracleReciprocal_LatestPrice is OrigamiVolatileCurveEmaOracleTestBase {
    function test_latestPrice_success() public {
        assertEq(
            oOracleReciprocal.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.000162227457871444e18
        );
        assertEq(
            oOracleReciprocal.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.000162227457871444e18
        );

        assertEq(
            oOracleReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.000162227457871444e18
        );
        assertEq(
            oOracleReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.000162227457871444e18
        );
    }

    function test_latestPrice_fail_range() public {
        vm.mockCall(
            address(STABLE_SWAP_NG),
            abi.encodeWithSelector(ICurveStableSwapNG.price_oracle.selector),
            abi.encode(0.989e18)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(STABLE_SWAP_NG), uint256(1e36)/0.989e18, 1.01e18));
        oOracleReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oOracleReciprocal.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        assertEq(spot, 1.000162227457871444e18);
        assertEq(hist, 1.000162227457871444e18);
        assertEq(baseAsset, address(USD0_TOKEN));
        assertEq(quoteAsset, address(USD0PP_TOKEN));
    }
}

contract OrigamiVolatileCurveEmaOracleNotReciprocal_LatestPrice is OrigamiVolatileCurveEmaOracleTestBase {
    function test_latestPrice_success() public {
        assertEq(
            oOracleNotReciprocal.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.999837798855607874e18
        );
        assertEq(
            oOracleNotReciprocal.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.999837798855607874e18
        );
        
        assertEq(
            oOracleNotReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.999837798855607874e18
        );
        assertEq(
            oOracleNotReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.999837798855607874e18
        );
    }

    function test_latestPrice_fail_range() public {
        vm.mockCall(
            address(STABLE_SWAP_NG),
            abi.encodeWithSelector(ICurveStableSwapNG.price_oracle.selector),
            abi.encode(0.989e18)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(STABLE_SWAP_NG), 0.989e18, 0.99e18));
        oOracleNotReciprocal.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oOracleNotReciprocal.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_UP
        );
        assertEq(spot, 0.999837798855607874e18);
        assertEq(hist, 0.999837798855607874e18);
        assertEq(baseAsset, address(USD0PP_TOKEN));
        assertEq(quoteAsset, address(USD0_TOKEN));
    }
}
