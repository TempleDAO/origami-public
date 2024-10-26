pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiCrossRateOracleTestBase is OrigamiTest {

    DummyOracle public oracle1;
    DummyOracle public oracle2;
    DummyOracle public oracle3;
    DummyOracle public oracle3_inverse;
    OrigamiStableChainlinkOracle public oOracle1;
    OrigamiStableChainlinkOracle public oOracle2;
    OrigamiStableChainlinkOracle public oOracle3;
    OrigamiStableChainlinkOracle public oOracle3_inverse;
    OrigamiCrossRateOracle public crOracle_1_2;
    OrigamiCrossRateOracle public crOracle_2_3;
    OrigamiCrossRateOracle public crOracle_2_3_inverse;
    OrigamiCrossRateOracle public crOracle_1_2_3;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");
    address public token3 = makeAddr("token3");
    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    function setupDaiUsdcOracle() internal {
        // 8 decimals
        oracle1 = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00044127e8,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            8
        );

        // 18 decimals for baseAsset and quoteAsset
        oOracle1 = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/USD",
                token1,
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            1e18,
            address(oracle1),
            100 days,
            Range.Data(0.95e18, 1.05e18),
            true,
            true
        );

        // 18 decimals
        oracle2 = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.00006620e18,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            18
        );

        // 6 decimals for baseAsset, 18 decimals for quoteAsset
        oOracle2 = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/USD",
                token2,
                6,
                INTERNAL_USD_ADDRESS,
                18
            ),
            333e18,
            address(oracle2),
            100 days,
            Range.Data(0.90e18, 1.10e18),
            true,
            true
        );

        // 24 decimals
        oracle3 = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.01e24,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            24
        );

        // 18 decimals for baseAsset, 6 decimals for quoteAsset
        oOracle3 = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "TOKEN3/USD",
                token3,
                18,
                INTERNAL_USD_ADDRESS,
                6
            ),
            0.99e18,
            address(oracle3),
            200 days,
            Range.Data(0.90e18, 1.10e18),
            true,
            true
        );

        // cross rate from 1 to 2
        crOracle_1_2 = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/TOKEN2",
                token1,
                18,
                token2,
                6
            ),
            address(oOracle1),
            address(oOracle2),
            address(0)
        );

        // cross rate from 2 to 3
        crOracle_2_3 = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/TOKEN3",
                token2,
                6,
                token3,
                6
            ),
            address(oOracle2),
            address(oOracle3),
            address(0)
        );

        // 24 decimals
        oracle3_inverse = new DummyOracle(
            DummyOracle.Answer({
                roundId: 1,
                answer: int256(uint256(1e24*1e24)/1.01e24),
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            }),
            24
        );

        // 18 decimals for baseAsset, 6 decimals for quoteAsset
        oOracle3_inverse = new OrigamiStableChainlinkOracle(
            origamiMultisig,
            IOrigamiOracle.BaseOracleParams(
                "USD/TOKEN3",
                INTERNAL_USD_ADDRESS,
                6,
                token3,
                18
            ),
            uint256(1e18*1e18)/0.99e18,
            address(oracle3_inverse),
            200 days,
            Range.Data(0.90e18, 1.10e18),
            true,
            true
        );

        // cross rate from 2 to 3 (inverse)
        crOracle_2_3_inverse = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN2/TOKEN3",
                token2,
                6,
                token3,
                6
            ),
            address(oOracle2),
            address(oOracle3_inverse),
            address(0)
        );

        // cross rate from  1 to 2 with 3 as PriceCheck
        crOracle_1_2_3 = new OrigamiCrossRateOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/TOKEN2/TOKEN3",
                token1,
                18,
                token2,
                6
            ),
            address(oOracle1),
            address(oOracle2),
            address(oOracle3)
        );
    }

    function _setUp() public {
        vm.warp(1672531200); // 1 Jan 2023
        vm.startPrank(origamiMultisig);
        setupDaiUsdcOracle();
        vm.stopPrank();
    }
}

contract OrigamiCrossRateOracleTestInit is OrigamiCrossRateOracleTestBase {
    function test_initialization() public {
        _setUp();
        assertEq(crOracle_1_2.decimals(), 18);
        assertEq(crOracle_1_2.precision(), 1e18);
        assertEq(crOracle_1_2.description(), "TOKEN1/TOKEN2");
        assertEq(address(crOracle_1_2.baseAssetOracle()), address(oOracle1));
        assertEq(address(crOracle_1_2.quoteAssetOracle()), address(oOracle2));
        assertEq(address(crOracle_1_2.priceCheckOracle()), address(0));
        assertEq(crOracle_1_2.multiply(), false);

        assertEq(crOracle_2_3.decimals(), 18);
        assertEq(crOracle_2_3.precision(), 1e18);
        assertEq(crOracle_2_3.description(), "TOKEN2/TOKEN3");
        assertEq(address(crOracle_2_3.baseAssetOracle()), address(oOracle2));
        assertEq(address(crOracle_2_3.quoteAssetOracle()), address(oOracle3));
        assertEq(address(crOracle_2_3.priceCheckOracle()), address(0));
        assertEq(crOracle_2_3.multiply(), false);

        assertEq(crOracle_2_3_inverse.decimals(), 18);
        assertEq(crOracle_2_3_inverse.precision(), 1e18);
        assertEq(crOracle_2_3_inverse.description(), "TOKEN2/TOKEN3");
        assertEq(address(crOracle_2_3_inverse.baseAssetOracle()), address(oOracle2));
        assertEq(address(crOracle_2_3_inverse.quoteAssetOracle()), address(oOracle3_inverse));
        assertEq(address(crOracle_2_3_inverse.priceCheckOracle()), address(0));
        assertEq(crOracle_2_3_inverse.multiply(), true);

        assertEq(crOracle_1_2_3.decimals(), 18);
        assertEq(crOracle_1_2_3.precision(), 1e18);
        assertEq(crOracle_1_2_3.description(), "TOKEN1/TOKEN2/TOKEN3");
        assertEq(address(crOracle_1_2_3.baseAssetOracle()), address(oOracle1));
        assertEq(address(crOracle_1_2_3.quoteAssetOracle()), address(oOracle2));
        assertEq(address(crOracle_1_2_3.priceCheckOracle()), address(oOracle3));
        assertEq(crOracle_1_2_3.multiply(), false);
    }

    function test_constructor_failure() public {
        _setUp();

        // base on this oracle doesn't match base (token1)
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN1/TOKEN2",
                    token1,
                    18,
                    token2,
                    6
                ),
                address(oOracle2), // TOKEN2/USD
                address(oOracle1), // TOKEN1/USD
                address(0)
            );
        }

        // cross asset isn't in the second oracle
        {
            OrigamiStableChainlinkOracle oOracleX = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN3/TOKEN2",
                    token3,
                    18,
                    token2,
                    6
                ),
                0.99e18,
                address(oracle3),
                200 days,
                Range.Data(0.90e18, 1.10e18),
                true,
                true
            );
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN1/TOKEN2",
                    token1,
                    18,
                    token2,
                    6
                ),
                address(oOracle1), // TOKEN1/USD
                address(oOracleX), // TOKEN3/TOKEN2
                address(0)
            );
        }

        // quote asset isn't in the second oracle
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
            new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN1/TOKEN2",
                    token1,
                    18,
                    token2,
                    6
                ),
                address(oOracle1), // TOKEN1/USD
                address(oOracle3), // TOKEN3/USD
                address(0)
            );
        }
    }

    function test_constructor_succeed_muldiv() public {
        _setUp();

        // Divide
        {
            OrigamiCrossRateOracle _ooracle = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN1/TOKEN2",
                    token1,
                    18,
                    token2,
                    6
                ),
                address(oOracle1), // TOKEN1/USD
                address(oOracle2), // TOKEN2/USD
                address(0)
            );
            assertEq(_ooracle.multiply(), false);
        }

        // Multiply
        {
            oOracle2 = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "USD/TOKEN2",
                    INTERNAL_USD_ADDRESS,
                    18,
                    token2,
                    6
                ),
                333e18,
                address(oracle2),
                100 days,
                Range.Data(0.90e18, 1.10e18),
                true,
                true
            );
            OrigamiCrossRateOracle _ooracle = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "TOKEN1/TOKEN2",
                    token1,
                    18,
                    token2,
                    6
                ),
                address(oOracle1), // TOKEN1/USD
                address(oOracle2), // USD/TOKEN2
                address(0)
            );
           assertEq(_ooracle.multiply(), true);
        }
    }

}

contract OrigamiCrossRateOracleTestLatestPrice_1_2 is OrigamiCrossRateOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success_1() public {
        // At floor
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.949937114163042406e18
        );
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.949937114163042407e18
        );

        // At ceiling
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.049930494601257396e18
        );
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.049930494601257397e18
        );
    }

    function test_latestPrice_success_2() public {
        // At floor
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.90e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.111601411111111111e18
        );
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.111601411111111112e18
        );

        // At ceiling
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.1e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.909492063636363636e18
        );
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.909492063636363637e18
        );
    }

    function test_latestPrice_fail_denominator_zero() public {
        oOracle2.setValidSpotPriceRange(0, 100e18);
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oOracle2), 
            0
        ));
        crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_success_numerator_zero() public {
        oOracle1.setValidSpotPriceRange(0, 100e18);
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0);
    }

    function test_historicPrice() public {
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.003003003003003003e18
        );
        assertEq(
            crOracle_1_2.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.003003003003003004e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        assertEq(
            crOracle_1_2.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.962509543413777798e18
        );
        assertEq(
            crOracle_1_2.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.962509543413777899e18
        );

        assertEq(
            crOracle_1_2.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            33_299.999999999988944400e18
        );
        assertEq(
            crOracle_1_2.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            33_300.000000000000033301e18
        );
    }

    function test_spot_convertAmount_baseToQuote() public {
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2.convertAmount(
                token1,
                99.962509543413777899e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_1_2.convertAmount(
                token1,
                99.962509543413777899e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6 + 1
        );

        assertEq(
            crOracle_1_2.convertAmount(
                token1,
                33_300.000000000000033301e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_1_2.convertAmount(
                token1,
                33_300.000000000000033301e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6+1
        );
    }
}

contract OrigamiCrossRateOracleTestLatestPrice_2_3 is OrigamiCrossRateOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success_2() public {
        // At floor
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.940594059405940594e18
        );
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.940594059405940595e18
        );

        // At ceiling
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.039603960396039603e18
        );
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.039603960396039604e18
        );
    }

    function test_latestPrice_success_3() public {
        // At floor
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.90e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.111184666666666666e18
        );
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.111184666666666667e18
        );

        // At ceiling
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.1e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.909151090909090909e18
        );
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.909151090909090910e18
        );
    }

    function test_latestPrice_fail_denominator_zero() public {
        oOracle3.setValidSpotPriceRange(0, 100e18);
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oOracle3), 
            0
        ));
        crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_success_numerator_zero() public {
        oOracle2.setValidSpotPriceRange(0, 100e18);
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0);
    }

    function test_historicPrice() public {
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            336.363636363636363636e18
        );
        assertEq(
            crOracle_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            336.363636363636363637e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        assertEq(
            crOracle_2_3.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100.993314e6
        );
        assertEq(
            crOracle_2_3.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100.993315e6
        );

        assertEq(
            crOracle_2_3.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            0.297297e6
        );
        assertEq(
            crOracle_2_3.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            0.297298e6
        );
    }

    function test_spot_convertAmount() public {
        assertEq(
            crOracle_2_3.convertAmount(
                token2,
                100.993315e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_2_3.convertAmount(
                token2,
                100.993315e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6 + 1
        );

        assertEq(
            crOracle_2_3.convertAmount(
                token2,
                0.297297e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.999899e6
        );
        assertEq(
            crOracle_2_3.convertAmount(
                token2,
                0.297297e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.999901e6
        );
    }
}

contract OrigamiCrossRateOracleTestLatestPrice_1_2_3 is OrigamiCrossRateOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success_1() public {
        // At floor
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.949937114163042406e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.949937114163042407e18
        );

        // At ceiling
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.049930494601257396e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.049930494601257397e18
        );
    }

    function test_latestPrice_success_2() public {
        // At floor
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.90e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.111601411111111111e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.111601411111111112e18
        );

        // At ceiling
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.1e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.909492063636363636e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.909492063636363637e18
        );
    }

    function test_latestPrice_fail_denominator_zero() public {
        oOracle2.setValidSpotPriceRange(0, 100e18);
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oOracle2), 
            0
        ));
        crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_success_numerator_zero() public {
        oOracle1.setValidSpotPriceRange(0, 100e18);
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0);
    }

    function test_historicPrice() public {
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.003003003003003003e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.003003003003003004e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        assertEq(
            crOracle_1_2_3.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.962509543413777798e18
        );
        assertEq(
            crOracle_1_2_3.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.962509543413777899e18
        );

        assertEq(
            crOracle_1_2_3.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            33_299.999999999988944400e18
        );
        assertEq(
            crOracle_1_2_3.convertAmount(
                token2,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            33_300.000000000000033301e18
        );
    }

    function test_spot_convertAmount_baseToQuote() public {
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_1_2_3.convertAmount(
                token1,
                99.962509543413777899e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_1_2_3.convertAmount(
                token1,
                99.962509543413777899e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6 + 1
        );

        assertEq(
            crOracle_1_2_3.convertAmount(
                token1,
                33_300.000000000000033301e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_1_2_3.convertAmount(
                token1,
                33_300.000000000000033301e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6+1
        );
    }

    function test_pricecheck() public {
        // update validate spot price range
        oOracle3.setValidSpotPriceRange(
            0.999e18, 1.111e18
        );

        // update answer
        oracle3.setAnswer(
            DummyOracle.Answer({
                roundId: 1,
                answer: 0.9989e24,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            })
        );

        // revert with BelowMinValidRange
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oracle3), 
            0.9989e18,
            0.999e18
        ));
        crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oracle3), 
            0.9989e18,
            0.999e18
        ));
        crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP);

        // history price fetch will success
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.003003003003003003e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.003003003003003004e18
        );

        // update answer
        oracle3.setAnswer(
            DummyOracle.Answer({
                roundId: 1,
                answer: 0.999e24,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            })
        );

        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.000375045172009612e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.000375045172009613e18
        );

        // update answer
        oracle3.setAnswer(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.111e24,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            })
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.000375045172009612e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.000375045172009613e18
        );

        // update answer
        oracle3.setAnswer(
            DummyOracle.Answer({
                roundId: 1,
                answer: 1.1111e24,
                startedAt: 0,
                updatedAtLag: 0,
                answeredInRound: 1
            })
        );

        // revert with BelowMinValidRange
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oracle3), 
            1.1111e18,
            1.111e18
        ));
        crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // history price fetch will success
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.003003003003003003e18
        );
        assertEq(
            crOracle_1_2_3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.003003003003003004e18
        );
    }
}

contract OrigamiCrossRateOracleTestLatestPrice_2_3_Multiply is OrigamiCrossRateOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success_2() public {
        oracle3_inverse.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            crOracle_2_3_inverse.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.95006289e18
        );
        assertEq(
            crOracle_2_3_inverse.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.95006289e18
        );
    }

    function test_latestPrice_success_numerator_zero() public {
        oOracle3_inverse.setValidSpotPriceRange(0, 100e18);
        oracle3_inverse.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(crOracle_2_3_inverse.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0);
    }

    function test_historicPrice() public {
        assertEq(
            crOracle_2_3_inverse.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            336.363636363636363633e18
        );
        assertEq(
            crOracle_2_3_inverse.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            336.363636363636363633e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100.993314e6
        );
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100.993315e6
        );

        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            0.297297e6
        );
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token3,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            0.297298e6
        );
    }

    function test_spot_convertAmount() public {
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token2,
                100.993315e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token2,
                100.993315e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6 + 1
        );

        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token2,
                0.297297e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.999899e6
        );
        assertEq(
            crOracle_2_3_inverse.convertAmount(
                token2,
                0.297297e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.9999e6
        );
    }
}