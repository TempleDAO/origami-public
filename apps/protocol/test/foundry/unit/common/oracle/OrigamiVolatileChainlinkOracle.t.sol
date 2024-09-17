pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiVolatileChainlinkOracle } from "contracts/common/oracle/OrigamiVolatileChainlinkOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiVolatileChainlinkOracleTestBase is OrigamiTest {

    DummyOracle public oracle1;
    OrigamiVolatileChainlinkOracle public oOracle1;

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
        oOracle1 = new OrigamiVolatileChainlinkOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/USD",
                token1,
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(oracle1),
            100 days,
            true,
            true
        );
        vm.stopPrank();
    }
}

contract OrigamiVolatileChainlinkOracleTestInit is OrigamiVolatileChainlinkOracleTestBase {
    function test_initialization1() public {
        _setUp();
        assertEq(oOracle1.decimals(), 18);
        assertEq(oOracle1.precision(), 1e18);
        assertEq(oOracle1.description(), "TOKEN1/USD");
        assertEq(oOracle1.assetScalingFactor(), 1e18);

        assertEq(address(oOracle1.priceOracle()), address(oracle1));
        assertEq(oOracle1.pricePrecisionScaleDown(), false); // gets scaled up
        assertEq(oOracle1.pricePrecisionScalar(), uint128(1e10)); // 10 ** (18 - 8)
        assertEq(oOracle1.priceStalenessThreshold(), 100 days);
        assertEq(oOracle1.validateRoundId(), true);
        assertEq(oOracle1.validateLastUpdatedAt(), true);
        
    }
}

contract OrigamiVolatileChainlinkOracleTestAdmin is OrigamiVolatileChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_matchAssets() public {
        assertEq(oOracle1.matchAssets(token1, INTERNAL_USD_ADDRESS), true);
        assertEq(oOracle1.matchAssets(INTERNAL_USD_ADDRESS, token1), true);
        assertEq(oOracle1.matchAssets(alice, INTERNAL_USD_ADDRESS), false);
        assertEq(oOracle1.matchAssets(INTERNAL_USD_ADDRESS, alice), false);
        assertEq(oOracle1.matchAssets(alice, token1), false);
        assertEq(oOracle1.matchAssets(token1, alice), false);
        assertEq(oOracle1.matchAssets(bob, alice), false);
    }
}

contract OrigamiVolatileChainlinkOracle1_LatestPrice is OrigamiVolatileChainlinkOracleTestBase {
    function setUp() public {
        _setUp();
        vm.startPrank(origamiMultisig);
    }

    function test_latestPrice_success() public {
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.00044127e18
        );
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.00044127e18
        );
    }

    function test_historicPrice() public {
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1.00044127e18
        );
        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1.00044127e18
        );
    }

    function test_latestPrices_sameRounding() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_UP
        );
        assertEq(spot, 1.00044127e18);
        assertEq(hist, 1.00044127e18);
        assertEq(baseAsset, address(token1));
        assertEq(quoteAsset, INTERNAL_USD_ADDRESS);
    }

    function test_latestPrices_differentRounding() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = oOracle1.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        assertEq(spot, 1.00044127e18);
        assertEq(hist, 1.00044127e18);
        assertEq(baseAsset, address(token1));
        assertEq(quoteAsset, INTERNAL_USD_ADDRESS);
    }

    function test_latestPrice_noValidation() public {
        vm.mockCall(
            address(oracle1),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1e8, 0, 0, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.InvalidOracleData.selector, address(oracle1)));
        oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN);

        // Again with no validation
        oOracle1 = new OrigamiVolatileChainlinkOracle(
            IOrigamiOracle.BaseOracleParams(
                "TOKEN1/USD",
                token1,
                18,
                INTERNAL_USD_ADDRESS,
                18
            ),
            address(oracle1),
            100 days,
            false,
            false
        );

        assertEq(
            oOracle1.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN),
            1e18
        );
    }
}
