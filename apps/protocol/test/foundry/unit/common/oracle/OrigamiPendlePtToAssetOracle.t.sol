pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

import { OrigamiPendlePtToAssetOracle } from "contracts/common/oracle/OrigamiPendlePtToAssetOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiPendlePtToAssetOracleTest is OrigamiTest {
    OrigamiPendlePtToAssetOracle public oOracle;

    address internal constant pendleOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

    address internal constant pt_sUSDE_market = 0xd1D7D99764f8a52Aff007b7831cc02748b2013b5;
    uint32 internal constant twapDuration = 900;

    address internal constant pt_sUSDe = 0x6c9f097e044506712B58EAC670c9a5fd4BCceF13;
    address internal constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public {
        fork("mainnet", 20308622);
        vm.warp(1721006984);

        oOracle = new OrigamiPendlePtToAssetOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT-sUSDe-26Sep24/DAI",
                pt_sUSDe,
                18,
                DAI,
                18
            ),
            pendleOracle,
            pt_sUSDE_market,
            twapDuration
        );
    }

    function test_initialization() public {
        assertEq(address(oOracle.pendleMarket()), pt_sUSDE_market);
        assertEq(oOracle.twapDuration(), twapDuration);

        assertEq(oOracle.baseAsset(), pt_sUSDe);
        assertEq(oOracle.quoteAsset(), DAI);
    }

    function test_latestPrice_spot() public {
        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.969695790921845659e18
        );
        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.969695790921845659e18
        );
    }

    function test_latestPrice_historic() public {
        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            0.969695790921845659e18
        );
        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.HISTORIC_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            0.969695790921845659e18
        );
    }

    function test_latestPrice_afterMaturity() public {
        skip(365 days);

        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_UP), 
            1e18
        );
        assertEq(
            oOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 
            1e18
        );
    }

}
