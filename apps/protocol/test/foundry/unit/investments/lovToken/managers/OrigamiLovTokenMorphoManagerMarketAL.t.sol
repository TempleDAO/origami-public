pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiLovTokenMorphoManagerMarketAL } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManagerMarketAL.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";

import { 
    OrigamiLovTokenMorphoManagerTestBase, 
    OrigamiLovTokenMorphoManagerTestAdmin,
    OrigamiLovTokenMorphoManagerTestAccess,
    OrigamiLovTokenMorphoManagerTestViews,
    OrigamiLovTokenMorphoManagerTestInvest,
    OrigamiLovTokenMorphoManagerTestExit,
    OrigamiLovTokenMorphoManagerTestRebalanceDown,
    OrigamiLovTokenMorphoManagerTestRebalanceUp
} from "./OrigamiLovTokenMorphoManager.t.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiVolatileChainlinkOracle } from "contracts/common/oracle/OrigamiVolatileChainlinkOracle.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiLovTokenMorphoManagerMarketALTestBase is OrigamiLovTokenMorphoManagerTestBase {
    using OrigamiMath for uint256;

    DummyOracle internal fixedPriceOracle;
    OrigamiVolatileChainlinkOracle internal morphoALToMarketALOracle;

    OrigamiLovTokenMorphoManagerMarketAL internal alManager;

    uint128 ORACLE_PRICE = 0.95e18;

    function setUp() virtual override public {
        super.setUp();

        TARGET_AL = TARGET_AL;
        USER_AL_FLOOR = convertAL(USER_AL_FLOOR);
        USER_AL_CEILING = convertAL(USER_AL_CEILING);
        REBALANCE_AL_FLOOR = convertAL(REBALANCE_AL_FLOOR);
        REBALANCE_AL_CEILING = convertAL(REBALANCE_AL_CEILING);

        fixedPriceOracle = new DummyOracle(
            DummyOracle.Answer(
                0,
                int128(ORACLE_PRICE),
                0,
                0,
                0
            ),
            18
        );

        morphoALToMarketALOracle = new OrigamiVolatileChainlinkOracle(
            IOrigamiOracle.BaseOracleParams(
                "dummy",
                address(0),
                18,
                address(0),
                18
            ),
            address(fixedPriceOracle),
            365 days,
            false,
            true
        );

        alManager = new OrigamiLovTokenMorphoManagerMarketAL(
            origamiMultisig, 
            address(sUsdeToken), 
            address(daiToken),
            address(usdeToken),
            address(lovToken),
            address(borrowLend),
            address(morphoALToMarketALOracle)
        );
        manager = alManager;

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(address(alManager));

        alManager.setOracles(address(sUsdeToDaiOracle), address(usdeToDaiOracle));
        alManager.setUserALRange(USER_AL_FLOOR, USER_AL_CEILING);
        alManager.setRebalanceALRange(REBALANCE_AL_FLOOR, REBALANCE_AL_CEILING);
        alManager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);

        lovToken.setManager(address(alManager));

        vm.stopPrank();
    }

    function convertAL(uint128 al) internal virtual override view returns (uint128) {
        return uint128(uint256(al).mulDiv(1e18, ORACLE_PRICE, OrigamiMath.Rounding.ROUND_UP));
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestAdmin is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestAdmin {
    event MorphoALToMarketALOracleSet(address indexed morphoALToMarketALOracle);

    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_initialization() override public {
        super.test_initialization();

        assertEq(alManager.morphoALToMarketALOracle(), address(morphoALToMarketALOracle));
    }

    function test_setMorphoALToMarketALOracle_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        alManager.setMorphoALToMarketALOracle(address(0));
    }

    function test_setMorphoALToMarketALOracle_success() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(alManager));
        emit MorphoALToMarketALOracleSet(alice);
        alManager.setMorphoALToMarketALOracle(alice);
        assertEq(alManager.morphoALToMarketALOracle(), alice);
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestAccess is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestAccess {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestViews is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestViews {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_reservesBalance() public override {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        uint256 expectedReserves = amount;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        doRebalanceDown(TARGET_AL, 0, 5);
        expectedReserves = 250e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.249999999999999999e18);

        doRebalanceUp(rebalanceALRange.ceiling-1, 0, 5);
        expectedReserves = 199.999999999700000444e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), rebalanceALRange.ceiling-1);

        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        expectedReserves = 195.083083082783083523e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.300553887221154995e18 - 1);
        
        assertEq(sUsdeToken.balanceOf(bob), 4.916916916916916921e18);
    }

    function test_liabilities_success() public override {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        doRebalanceDown(TARGET_AL, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200e18 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200.584395999999999935e18);

        doRebalanceUp(rebalanceALRange.ceiling-1, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 149.999999999700000397e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 150.438296999699123754e18);

        // Exits don't affect liabilities
        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 149.999999999700000397e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 150.438296999699123754e18);
    }

    function test_as_price_changes() public {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        // Before a price update
        {
            (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
            {
                assertEq(assets, 250e18);
                assertEq(liabilities, 200e18 + 1);
                assertEq(ratio, 1.25e18 - 1);
            }
            (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
            {
                assertEq(assets, 250e18);
                assertEq(liabilities, 200.584395999999999935e18);
                assertEq(ratio, 1.246358166365044667e18);
            }
            assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 5e18 + 1);
            assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 5.059130715067248792e18);
        }
        
        vm.mockCall(
            address(redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8, 1711289195, 1711289195, 1)
        );

        // After a price update, liabilities are worth more in asset terms
        {
            (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
            {
                assertEq(assets, 250e18);
                assertEq(liabilities, 201.592357788944723747e18);
                assertEq(ratio, 1.240126375533219442e18);
            }
            (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
            {
                assertEq(assets, 250e18);
                assertEq(liabilities, 200.584395999999999935e18);
                assertEq(ratio, 1.246358166365044667e18);
            }
            assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 5.164473801678060566e18);
            assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 5.059130715067248792e18);
        }
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestInvest is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestInvest {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_maxInvest_reserveToken() public override {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedAvailable);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 100_000e18);
            assertEq(manager.reservesBalance(), 100_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedAvailable);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 100_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 71_428.571428571999999997e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 499_999.999999999999999992e18;
            uint256 expectedLiabilities = 399_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 401_168.791999999999866109e18);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e6;
            deal(address(sUsdeToken), alice, investAmount);
            vm.startPrank(alice);
            sUsdeToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(sUsdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.25e18, 1.428571428571430002e18, 1.428571428571430000e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
            exitLovToken(alice, amountOut, alice);
        }
    }

    function test_maxInvest_reserveToken_withMaxTotalSupply() public override {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);
        uint256 maxTotalSupply = 200_000e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            // share price = 1, +fees
            assertEq(manager.maxInvest(address(sUsdeToken)), 210_526.315789473684210526e18);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 100_000e18);
            assertEq(manager.reservesBalance(), 100_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            // share price > 1, +fees
            assertEq(manager.maxInvest(address(sUsdeToken)), 116_343.490304709141274237e18);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 100_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 71_428.571428571999999997e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 499_999.999999999999999992e18;
            uint256 expectedLiabilities = 399_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 401_168.791999999999866109e18);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e6;
            deal(address(sUsdeToken), alice, investAmount);
            vm.startPrank(alice);
            sUsdeToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(sUsdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.25e18, 1.428571428571430002e18, 1.428571428571430000e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
            exitLovToken(alice, amountOut, alice);
        }
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestExit is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestExit {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_maxExit_reserveToken() public override {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(0, 500, 0);
        
        // No token supply no reserves
        {
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(sUsdeToken)), 0);
        }

        // with reserves, no liabilities. Capped at total supply (10e18)
        {
            uint256 totalSupply = 20_000e18;
            uint256 shares = investLovToken(alice, totalSupply / 2);
            assertEq(shares, 10_000e18);
            assertEq(manager.reservesBalance(), 10_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(sUsdeToken)), 10_000e18);
        }

        // Only rebalance a little. A/L is still 11. Still capped at total supply (10e18)
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxExit(address(sUsdeToken)), 10_000e18);
        }

        // Rebalance down properly
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 49_999.999999999999999992e18;
            uint256 expectedLiabilities = 39_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 40_116.879199999999986604e18);
            assertEq(manager.maxExit(address(sUsdeToken)), 4_511.278195488842105262e18);
        }

        {
            vm.startPrank(origamiMultisig);
            manager.setUserALRange(convertAL(1.111111112e18), 2e18);
            manager.setRebalanceALRange(convertAL(1.111111112e18), 2e18);
            doRebalanceUp(1.5e18, 0, 5);
            assertEq(manager.maxExit(address(sUsdeToken)), 8_187.134484210526322552e18);
        }

        // An external withdraw of supply does not impact our collateral and amount
        // which can be exited
        {
            assertEq(borrowLend.availableToBorrow(), 9_979_248.978174019999743496e18);
            assertEq(borrowLend.availableToWithdraw(), 29_999.999999999999999996e18);

            vm.startPrank(origamiMultisig);
            IMorpho morpho = borrowLend.morpho();
            morpho.withdraw(borrowLend.getMarketParams(), 9_979_000e18, 0, origamiMultisig, origamiMultisig);
            vm.stopPrank();

            assertEq(borrowLend.availableToBorrow(), 248.978174019999743496e18);
            assertEq(borrowLend.availableToWithdraw(), 29_999.999999999999999996e18);
        }

        assertEq(manager.maxExit(address(sUsdeToken)), 8_187.134484210526322552e18);
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestRebalanceDown is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestRebalanceDown {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_rebalanceDown_success_al_floor_force() public override {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(convertAL(uint128(targetAL + 0.01e18)), rebalanceALRange.ceiling);
            
        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
            deal(address(sUsdeToken), address(swapper), reservesAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.249999999999999999e18, 1.26e18));
        manager.rebalanceDown(params);

        uint256 expectedCollateralAdded = 200_000e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            targetAL-1
        );
        manager.forceRebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
    }
}

contract OrigamiLovTokenMorphoManagerMarketALTestRebalanceUp is OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestRebalanceUp {
    function setUp() override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) public {
        super.setUp();
    }

    function convertAL(uint128 al) override(OrigamiLovTokenMorphoManagerMarketALTestBase, OrigamiLovTokenMorphoManagerTestBase) internal view returns (uint128) {
        return super.convertAL(al);
    }

    function test_rebalanceUp_fail_al_ceiling() public override {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = rebalanceALRange.ceiling+1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, targetAL, rebalanceALRange.ceiling));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_success_al_floor_force() public override {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.1e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, TARGET_AL-1, targetAL, 1.333333333334e18));
        manager.rebalanceUp(params);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            TARGET_AL-1,
            targetAL
        );
        manager.forceRebalanceUp(params);
    }
}
