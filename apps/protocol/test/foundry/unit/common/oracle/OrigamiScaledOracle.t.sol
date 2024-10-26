pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiFixedPriceOracle } from "contracts/common/oracle/OrigamiFixedPriceOracle.sol";
import { OrigamiScaledOracle } from "contracts/common/oracle/OrigamiScaledOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiScaledOracleTestBase is OrigamiTest {
    OrigamiFixedPriceOracle public referenceOracle;
    OrigamiFixedPriceOracle public scalarOracle;

    OrigamiScaledOracle public scaledOracleMultiply;
    OrigamiScaledOracle public scaledOracleDivide;

    address public token1 = makeAddr("token1");
    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;
    address public constant INTERNAL_CONSTANT_ADDRESS = address(0);

    uint256 public constant REF_PRICE = 0.512312312312312313e18;
    uint256 public constant SCALAR = 0.953e18;

    function setupOracles() internal {
        // 6 decimals for baseAsset, 18 decimals for quoteAsset
        referenceOracle = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/USD",
                token1,
                6,
                INTERNAL_USD_ADDRESS,
                18
            ),
            REF_PRICE,
            address(0)
        );

        scalarOracle = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT_DISCOUNT_FACTOR",
                INTERNAL_CONSTANT_ADDRESS,
                18,
                INTERNAL_CONSTANT_ADDRESS,
                18
            ),
            SCALAR,
            address(0)
        );

        // referenceOracle * scalarOracle
        scaledOracleMultiply = new OrigamiScaledOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/USD * DF",
                token1,
                6,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(referenceOracle),
            address(scalarOracle),
            true
        );

        // referenceOracle / scalarOracle
        scaledOracleDivide = new OrigamiScaledOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/USD / DF",
                token1,
                6,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(referenceOracle),
            address(scalarOracle),
            false
        );
    }

    function _setUp() public {
        vm.warp(1672531200); // 1 Jan 2023
        vm.startPrank(origamiMultisig);
        setupOracles();
        vm.stopPrank();
    }
}

contract OrigamiScaledOracleTestInit is OrigamiScaledOracleTestBase {
    function test_initialization() public {
        _setUp();
        assertEq(scaledOracleMultiply.decimals(), 18);
        assertEq(scaledOracleMultiply.precision(), 1e18);
        assertEq(scaledOracleMultiply.description(), "TOKEN2/USD * DF");
        assertEq(address(scaledOracleMultiply.baseAsset()), address(token1));
        assertEq(address(scaledOracleMultiply.quoteAsset()), INTERNAL_USD_ADDRESS);
        assertEq(scaledOracleMultiply.assetScalingFactor(), 1e6);
        assertEq(scaledOracleMultiply.multiply(), true);

        assertEq(scaledOracleDivide.decimals(), 18);
        assertEq(scaledOracleDivide.precision(), 1e18);
        assertEq(scaledOracleDivide.description(), "TOKEN2/USD / DF");
        assertEq(address(scaledOracleDivide.baseAsset()), address(token1));
        assertEq(address(scaledOracleDivide.quoteAsset()), INTERNAL_USD_ADDRESS);
        assertEq(scaledOracleDivide.assetScalingFactor(), 1e6);
        assertEq(scaledOracleDivide.multiply(), false);
    }

    function test_constructor_failure() public {
        _setUp();

        // not matching baseAsset
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, INTERNAL_USD_ADDRESS));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD / DF",
                    INTERNAL_USD_ADDRESS,
                    6,
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                false
            );
        }

        // not matching quoteAsset
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(token1)));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD / DF",
                    token1,
                    6,
                    token1,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                false
            );
        }

        // different scaling factor
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD / DF",
                    token1,
                    18,
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                false
            );
        }

        // non-matching scalar baseAsset & quoteAsset
        {
            scalarOracle = new OrigamiFixedPriceOracle(
                IOrigamiOracle.BaseOracleParams(
                    "PT_DISCOUNT_FACTOR",
                    token1,
                    18,
                    INTERNAL_CONSTANT_ADDRESS,
                    18
                ),
                0.953e18,
                address(0)
            );

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD * DF",
                    token1,
                    6,
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                true
            );

            scalarOracle = new OrigamiFixedPriceOracle(
                IOrigamiOracle.BaseOracleParams(
                    "PT_DISCOUNT_FACTOR",
                    INTERNAL_CONSTANT_ADDRESS,
                    18,
                    token1,
                    18
                ),
                0.953e18,
                address(0)
            );

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD * DF",
                    token1,
                    6,
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                true
            );
        }

        // decimals not matching
        {
            scalarOracle = new OrigamiFixedPriceOracle(
                IOrigamiOracle.BaseOracleParams(
                    "PT_DISCOUNT_FACTOR",
                    INTERNAL_CONSTANT_ADDRESS,
                    6,
                    INTERNAL_CONSTANT_ADDRESS,
                    18
                ),
                0.953e18,
                address(0)
            );

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiScaledOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN2/USD * DF",
                    token1,
                    6,
                    INTERNAL_USD_ADDRESS,
                    18
                ),
                address(referenceOracle),
                address(scalarOracle),
                true
            );
        }
    }
}

contract OrigamiScaledOracleTestLatestPriceMultiply is OrigamiScaledOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success() public {
        assertEq(
            scaledOracleMultiply.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            REF_PRICE * SCALAR / 1e18
        );

        assertEq(
            scaledOracleMultiply.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            REF_PRICE * SCALAR / 1e18 + 1
        );
    }

    function test_convertAmount() public {
        assertEq(
            scaledOracleMultiply.convertAmount(
                token1,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            REF_PRICE * SCALAR / 1e18 * 100
        );
        assertEq(
            scaledOracleMultiply.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e18 * 1e18 * 1e6 / (REF_PRICE * SCALAR)
        );

        assertEq(
            scaledOracleMultiply.convertAmount(
                token1,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            (REF_PRICE * SCALAR / 1e18 + 1) * 100
        );
        assertEq(
            scaledOracleMultiply.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e18 * 1e18 * 1e6 / (REF_PRICE * SCALAR) + 1
        );
    }
}

contract OrigamiScaledOracleTestLatestPriceDivide is OrigamiScaledOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success() public {
        assertEq(
            scaledOracleDivide.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1e18 * REF_PRICE / SCALAR
        );

        assertEq(
            scaledOracleDivide.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            1e18 * REF_PRICE / SCALAR + 1
        );
    }

    function test_latestPrice_failure() public {
        // Zero price
        scalarOracle = new OrigamiFixedPriceOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT_DISCOUNT_FACTOR",
                INTERNAL_CONSTANT_ADDRESS,
                18,
                INTERNAL_CONSTANT_ADDRESS,
                18
            ),
            0,
            address(0)
        );

        scaledOracleDivide = new OrigamiScaledOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/USD / DF",
                token1,
                6,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(referenceOracle),
            address(scalarOracle),
            false
        );

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(scalarOracle), 
            0
        ));
        scaledOracleDivide.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_convertAmount() public {
        assertEq(
            scaledOracleDivide.convertAmount(
                token1,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            1e18 * REF_PRICE / SCALAR * 100
        );
        assertEq(
            scaledOracleDivide.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e18 * 1e6 / (1e18 * REF_PRICE / SCALAR)
        );

        assertEq(
            scaledOracleDivide.convertAmount(
                token1,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            (1e18 * REF_PRICE / SCALAR + 1) * 100
        );
        assertEq(
            scaledOracleDivide.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e18 * 1e6 / (1e18 * REF_PRICE / SCALAR) + 1
        );
    }
}
