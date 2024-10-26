pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiFixedPriceOracle } from "contracts/common/oracle/OrigamiFixedPriceOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiOracleBase } from "contracts/common/oracle/OrigamiOracleBase.sol";

contract MockOracle is OrigamiOracleBase {
    constructor (BaseOracleParams memory baseParams) OrigamiOracleBase(baseParams) {}

    function latestPrice(
        PriceType /*priceType*/,
        OrigamiMath.Rounding /*roundingMode*/
    ) public override pure returns (uint256 price) {
        return 1.0e18;
    }
}

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiFixedPriceOracleTestBase is OrigamiTest {
    OrigamiFixedPriceOracle public oOracleFixed;
    OrigamiFixedPriceOracle public oOracleFixedNoCheck;

    MockOracle public oOracleCheck;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");

    function setUp() public {
        vm.warp(1672531200); // 1 Jan 2023

        oOracleCheck = new MockOracle(
            IOrigamiOracle.BaseOracleParams(
                "token1/token2",
                token1,
                18,
                token2,
                18
            )
        );

        oOracleFixed = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "token1/token2",
                token1,
                18,
                token2,
                18
            ),
            0.9999e18,
            address(oOracleCheck)
        );

        oOracleFixedNoCheck = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "token1/token2",
                token1,
                18,
                token2,
                18
            ),
            1.1e18,
            address(0)
        );
    }
}

contract OrigamiFixedPriceOracleTestInit is OrigamiFixedPriceOracleTestBase {
    function test_initialization_fixed() public {
        assertEq(oOracleFixed.decimals(), 18);
        assertEq(oOracleFixed.precision(), 1e18);
        assertEq(oOracleFixed.description(), "token1/token2");
        assertEq(oOracleFixed.assetScalingFactor(), 1e18);
        assertEq(oOracleFixed.baseAsset(), token1);
        assertEq(oOracleFixed.quoteAsset(), token2);

        assertEq(address(oOracleFixed.priceCheckOracle()), address(oOracleCheck));
    }

    function test_initialization_noCheck() public {
        assertEq(oOracleFixedNoCheck.decimals(), 18);
        assertEq(oOracleFixedNoCheck.precision(), 1e18);
        assertEq(oOracleFixedNoCheck.description(), "token1/token2");
        assertEq(oOracleFixedNoCheck.assetScalingFactor(), 1e18);
        assertEq(oOracleFixedNoCheck.baseAsset(), token1);
        assertEq(oOracleFixedNoCheck.quoteAsset(), token2);

        assertEq(address(oOracleFixedNoCheck.priceCheckOracle()), address(0));
    }
}

contract OrigamiFixedPriceOracleWithCheck_LatestPrice is OrigamiFixedPriceOracleTestBase {
    function test_latestPrice_success() public {
        assertEq(
            oOracleFixed.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.9999e18
        );
        assertEq(
            oOracleFixed.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.9999e18
        );

        assertEq(
            oOracleFixed.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.9999e18
        );
        assertEq(
            oOracleFixed.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.9999e18
        );
    }

    function test_latestPrice_fail_check() public {
        vm.mockCallRevert(
            address(oOracleCheck),
            abi.encodeWithSelector(MockOracle.latestPrice.selector),
            "bad price"
        );

        vm.expectRevert("bad price");
        oOracleFixed.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP);
    }
}
