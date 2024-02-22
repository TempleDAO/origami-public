pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { Range } from "contracts/libraries/Range.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiStableChainlinkOracleTestBase is OrigamiTest {

    DummyOracle public oracle1;
    DummyOracle public oracle2;
    DummyOracle public oracle3;
    OrigamiStableChainlinkOracle public oOracle1;
    OrigamiStableChainlinkOracle public oOracle2;
    OrigamiStableChainlinkOracle public oOracle3;

    address public token1 = makeAddr("token1");
    address public token2 = makeAddr("token2");
    address public token3 = makeAddr("token3");
    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    function _setUp() internal {
        vm.warp(1672531200); // 1 Jan 2023
        vm.startPrank(origamiMultisig);

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
            "TOKEN1/USD",
            token1,
            18,
            INTERNAL_USD_ADDRESS,
            18,
            1e18,
            address(oracle1),
            100 days,
            Range.Data(0.95e18, 1.05e18)
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
            "TOKEN2/USD",
            token2,
            6,
            INTERNAL_USD_ADDRESS,
            18,
            333e18,
            address(oracle2),
            100 days,
            Range.Data(0.95e18, 1.05e18)
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
            "TOKEN3/USD",
            token3,
            18,
            INTERNAL_USD_ADDRESS,
            6,
            0.99e18,
            address(oracle3),
            200 days,
            Range.Data(0.95e18, 1.05e18)
        );

        vm.stopPrank();
    }
}

contract OrigamiStableChainlinkOracleTestInit is OrigamiStableChainlinkOracleTestBase {
    function test_initialization1() public {
        _setUp();
        assertEq(address(oOracle1.owner()), origamiMultisig);
        assertEq(oOracle1.decimals(), 18);
        assertEq(oOracle1.precision(), 1e18);
        assertEq(oOracle1.description(), "TOKEN1/USD");
        assertEq(oOracle1.assetScalingFactor(), 1e18);
        assertEq(oOracle1.stableHistoricPrice(), 1e18);

        assertEq(address(oOracle1.spotPriceOracle()), address(oracle1));
        assertEq(oOracle1.spotPricePrecisionScaleDown(), false); // gets scaled up
        assertEq(oOracle1.spotPricePrecisionScalar(), uint128(1e10)); // 10 ** (18 - 8)
        assertEq(oOracle1.spotPriceStalenessThreshold(), 100 days);
        (uint128 floor, uint128 ceiling) = oOracle1.validSpotPriceRange();
        assertEq(floor, 0.95e18);
        assertEq(ceiling, 1.05e18);
    }

    function test_initialization2() public {
        _setUp();
        assertEq(address(oOracle2.owner()), origamiMultisig);
        assertEq(oOracle2.decimals(), 18);
        assertEq(oOracle2.precision(), 1e18);
        assertEq(oOracle2.description(), "TOKEN2/USD");
        assertEq(oOracle2.assetScalingFactor(), 1e6);
        assertEq(oOracle2.stableHistoricPrice(), 333e18);

        assertEq(address(oOracle2.spotPriceOracle()), address(oracle2));
        assertEq(oOracle2.spotPricePrecisionScaleDown(), false); // gets scaled up
        assertEq(oOracle2.spotPricePrecisionScalar(), uint128(1)); // 10 ** (18 - 18)
        assertEq(oOracle2.spotPriceStalenessThreshold(), 100 days);
        (uint128 floor, uint128 ceiling) = oOracle2.validSpotPriceRange();
        assertEq(floor, 0.95e18);
        assertEq(ceiling, 1.05e18);
    }

    function test_initialization3() public {
        _setUp();
        assertEq(address(oOracle3.owner()), origamiMultisig);
        assertEq(oOracle3.decimals(), 18);
        assertEq(oOracle3.precision(), 1e18);
        assertEq(oOracle3.description(), "TOKEN3/USD");
        assertEq(oOracle3.assetScalingFactor(), 1e30);
        assertEq(oOracle3.stableHistoricPrice(), 0.99e18);

        assertEq(address(oOracle3.spotPriceOracle()), address(oracle3));
        assertEq(oOracle3.spotPricePrecisionScaleDown(), true); // gets scaled down
        assertEq(oOracle3.spotPricePrecisionScalar(), uint128(1e6)); // 10 ** (24 - 18)
        assertEq(oOracle3.spotPriceStalenessThreshold(), 200 days);
        (uint128 floor, uint128 ceiling) = oOracle3.validSpotPriceRange();
        assertEq(floor, 0.95e18);
        assertEq(ceiling, 1.05e18);
    }
}

contract OrigamiStableChainlinkOracleTestAdmin is OrigamiStableChainlinkOracleTestBase {
    event ValidPriceRangeSet(uint128 validFloor, uint128 validCeiling);

    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_setValidSpotPriceRange_fail() public {
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 5, 4));
        oOracle1.setValidSpotPriceRange(5, 4);
    }

    function test_setValidSpotPriceRange_success() public {
        vm.expectEmit(address(oOracle1));
        emit ValidPriceRangeSet(1e18, 2e18);
        oOracle1.setValidSpotPriceRange(1e18, 2e18);
        
        (uint128 floor, uint128 ceiling) = oOracle1.validSpotPriceRange();
        assertEq(floor, 1e18);
        assertEq(ceiling, 2e18);
    }
}

contract OrigamiStableChainlinkOracleTestAccess is OrigamiStableChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
    }

    function test_access_setValidSpotPriceRange() public {
        expectElevatedAccess();
        oOracle1.setValidSpotPriceRange(1, 2);
    }
}

contract OrigamiStableChainlinkOracle1_LatestPrice is OrigamiStableChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_fail_stale() public {
        // 100 days old and was answered in this round
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 100 days + 1, // 100 days old...
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.StalePrice.selector, 
            address(oracle1),
            block.timestamp - (100 days + 1),
            1.00044127e8
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // 100 days old but was answered in a future round
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 100 days + 1,
            answeredInRound: 2
        }));

        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1.00044127e18
        );
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            1.00044127e18
        );

        // Just in time
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 100 days,
            answeredInRound: 1
        }));
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.00044127e18
        );
    }

    function test_latestPrice_fail_negative() public {
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: -1.00044127e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oracle1), 
            -1.00044127e8
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_fail_range() public {
        // Below floor
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e8-1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oracle1), 
            0.94999999e18,
            0.95e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // Above ceiling
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e8 + 1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oracle1), 
            1.05000001e18,
            1.05e18
        ));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_success_range() public {
        // At floor
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0.95e18);
        assertEq(oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 0.95e18);

        // At ceiling
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.05e18);
        assertEq(oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 1.05e18);
    }

    function test_historicPrice() public {
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1e18
        );
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        assertEq(spot, 1.00044127e18);
        assertEq(hist, 1e18);
        assertEq(baseAsset, address(token1));
        assertEq(quoteAsset, INTERNAL_USD_ADDRESS);
    }

    function test_spot_convertAmount_quoteToBase() public {
        oracle1.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e8,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            oOracle1.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.955892463332705177e18
        );
        assertEq(
            oOracle1.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.955892463332705178e18
        );

        assertEq(
            oOracle1.convertAmount(
                INTERNAL_USD_ADDRESS,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.955892463332705178e18
        );
        assertEq(
            oOracle1.convertAmount(
                INTERNAL_USD_ADDRESS,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.955892463332705178e18
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
            oOracle1.convertAmount(
                token1,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e18
        );
        assertEq(
            oOracle1.convertAmount(
                token1,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e18 + 1
        );

        assertEq(
            oOracle1.convertAmount(
                token1,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.955892463332705178e18
        );
        assertEq(
            oOracle1.convertAmount(
                token1,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.955892463332705178e18
        );
    }
}

contract OrigamiStableChainlinkOracle2_LatestPrice is OrigamiStableChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_fail_stale() public {
        // 100 days old and was answered in this round
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e18,
            startedAt: 0,
            updatedAtLag: 100 days + 1, // 100 days old...
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.StalePrice.selector, 
            address(oracle2),
            block.timestamp - (100 days + 1),
            1.00044127e18
        ));
        oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // 100 days old but was answered in a future round
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e18,
            startedAt: 0,
            updatedAtLag: 100 days + 1,
            answeredInRound: 2
        }));

        assertEq(
            oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1.00044127e18
        );
        assertEq(
            oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            1.00044127e18
        );

        // Just in time
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e18,
            startedAt: 0,
            updatedAtLag: 100 days,
            answeredInRound: 1
        }));
        assertEq(
            oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.00044127e18
        );
    }

    function test_latestPrice_fail_negative() public {
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: -1.00044127e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oracle2), 
            -1.00044127e18
        ));
        oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_fail_range() public {
        // Below floor
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e18-1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oracle2), 
            0.95e18 - 1,
            0.95e18
        ));
        oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // Above ceiling
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e18 + 1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oracle2), 
            1.05e18 + 1,
            1.05e18
        ));
        oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_success_range() public {
        // At floor
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0.95e18);
        assertEq(oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 0.95e18);

        // At ceiling
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.05e18);
        assertEq(oOracle2.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 1.05e18);
    }

    function test_historicPrice() public {
        assertEq(
            oOracle2.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            333e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            oOracle2.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.955892e6
        );
        assertEq(
            oOracle2.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.955893e6
        );

        assertEq(
            oOracle2.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            0.300300e6
        );
        assertEq(
            oOracle2.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            0.300301e6
        );
    }

    function test_spot_convertAmount_baseToQuote() public {
        oracle2.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e18,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            oOracle2.convertAmount(
                token2,
                99.955893e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100.000000536904110000e18
        );
        assertEq(
            oOracle2.convertAmount(
                token2,
                99.955893e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100.000000536904110000e18
        );
        
        assertEq(
            oOracle2.convertAmount(
                token2,
                0.300301e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100.000233e18
        );
        assertEq(
            oOracle2.convertAmount(
                token2,
                0.300301e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100.000233e18
        );
    }
}

contract OrigamiStableChainlinkOracle3_LatestPrice is OrigamiStableChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_fail_stale() public {
        // 200 days old and was answered in this round
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.000441275e24,
            startedAt: 0,
            updatedAtLag: 200 days + 1, // 200 days old...
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.StalePrice.selector, 
            address(oracle3),
            block.timestamp - (200 days + 1),
            1.000441275e24
        ));
        oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // 200 days old but was answered in a future round
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.000441275e24,
            startedAt: 0,
            updatedAtLag: 200 days + 1,
            answeredInRound: 2
        }));

        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1.000441275e18
        );
        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            1.000441275e18
        );

        // Just in time
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.000441275e24,
            startedAt: 0,
            updatedAtLag: 200 days,
            answeredInRound: 1
        }));
        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.000441275e18
        );
    }

    function test_latestPrice_fail_negative() public {
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: -1.000441275e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));

        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.InvalidPrice.selector, 
            address(oracle3), 
            -1.000441275e24
        ));
        oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function test_latestPrice_fail_range() public {
        // Below floor
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e24-1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.BelowMinValidRange.selector, 
            address(oracle3), 
            0.95e18 - 1,
            0.95e18
        ));
        oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // OK for ROUND_UP
        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP),
            0.95e18
        );

        // Above ceiling
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e24 + 1,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        vm.expectRevert(abi.encodeWithSelector(
            IOrigamiOracle.AboveMaxValidRange.selector, 
            address(oracle3), 
            1.05e18 + 1,
            1.05e18
        ));
        oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP);

        // OK for ROUND_DOWN
        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1.05e18
        );
    }

    function test_latestPrice_success_range() public {
        // At floor
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 0.95e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0.95e18);
        assertEq(oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 0.95e18);

        // At ceiling
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.05e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.05e18);
        assertEq(oOracle3.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 1.05e18);
    }

    function test_historicPrice() public {
        assertEq(
            oOracle3.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.99e18
        );
    }

    function test_spot_convertAmount_quoteToBase() public {
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            oOracle3.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            99.955892463332705177e18
        );
        assertEq(
            oOracle3.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e6,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            99.955892463332705178e18
        );

        assertEq(
            oOracle3.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            101.010101010101010101e18
        );
        assertEq(
            oOracle3.convertAmount(
                INTERNAL_USD_ADDRESS,
                100e6,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            101.010101010101010102e18
        );
    }

    function test_spot_convertAmount_baseToQuote() public {
        oracle3.setAnswer(DummyOracle.Answer({
            roundId: 1,
            answer: 1.00044127123123123123e24,
            startedAt: 0,
            updatedAtLag: 0,
            answeredInRound: 1
        }));
        assertEq(
            oOracle3.convertAmount(
                token3,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100.0e6
        );
        assertEq(
            oOracle3.convertAmount(
                token3,
                99.955892463332705178e18,
                IOrigamiOracle.PriceType.SPOT_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100.0e6 + 1
        );
        
        assertEq(
            oOracle3.convertAmount(
                token3,
                101.010101010101010102e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_DOWN
            ), 
            100e6
        );
        assertEq(
            oOracle3.convertAmount(
                token3,
                101.010101010101010102e18,
                IOrigamiOracle.PriceType.HISTORIC_PRICE, 
                OrigamiMath.Rounding.ROUND_UP
            ), 
            100e6 + 1
        );
    }
}
