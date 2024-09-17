pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_sUSDe_USDT_IntegrationTestBase } from "test/foundry/integration/lov-sUSDe-USDT/Origami_lov_sUSDe_USDT_IntegrationTestBase.t.sol";
import { Origami_lov_sUSDe_USDT_TestConstants as Constants } from "test/foundry/deploys/lov-sUSDe-USDT/Origami_lov_sUSDe_USDT_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_sUSDe_USDT_IntegrationTest is Origami_lov_sUSDe_USDT_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_sUSDe_USDT_initialization() public {
        {
            assertEq(address(lovTokenContracts.lovToken.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovToken.manager()), address(lovTokenContracts.lovTokenManager));
            assertEq(lovTokenContracts.lovToken.annualPerformanceFeeBps(), Constants.PERFORMANCE_FEE_BPS);
        }

        {
            assertEq(address(lovTokenContracts.lovTokenManager.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovTokenManager.lovToken()), address(lovTokenContracts.lovToken));
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 0);

            (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = lovTokenContracts.lovTokenManager.getFeeConfig();
            assertEq(minDepositFeeBps, Constants.MIN_DEPOSIT_FEE_BPS);
            assertEq(minExitFeeBps, Constants.MIN_EXIT_FEE_BPS);
            assertEq(feeLeverageFactor, Constants.FEE_LEVERAGE_FACTOR);

            (uint128 floor, uint128 ceiling) = lovTokenContracts.lovTokenManager.userALRange();
            assertEq(floor, Constants.USER_AL_FLOOR);
            assertEq(ceiling, Constants.USER_AL_CEILING);
            (floor, ceiling) = lovTokenContracts.lovTokenManager.rebalanceALRange();
            assertEq(floor, Constants.REBALANCE_AL_FLOOR);
            assertEq(ceiling, Constants.REBALANCE_AL_CEILING);

            assertEq(address(lovTokenContracts.lovTokenManager.debtToken()), address(externalContracts.usdtToken));
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.sUsdeToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.sUsdeToUsdtOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.usdeToUsdtOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.usdeToUsdtOracle.description(), "USDe/USDT");
            assertEq(lovTokenContracts.usdeToUsdtOracle.decimals(), 18);
            assertEq(lovTokenContracts.usdeToUsdtOracle.precision(), 1e18);

            assertEq(lovTokenContracts.usdeToUsdtOracle.stableHistoricPrice(), Constants.USDE_USD_HISTORIC_STABLE_PRICE);
            assertEq(address(lovTokenContracts.usdeToUsdtOracle.spotPriceOracle()), address(externalContracts.redstoneUsdeToUsdOracle));
            assertEq(lovTokenContracts.usdeToUsdtOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.usdeToUsdtOracle.spotPricePrecisionScalar(), 1e10); // Redstone oracle is 8dp
            assertEq(lovTokenContracts.usdeToUsdtOracle.spotPriceStalenessThreshold(), Constants.USDE_USD_STALENESS_THRESHOLD);
            (uint128 min, uint128 max) = lovTokenContracts.usdeToUsdtOracle.validSpotPriceRange();
            assertEq(min, Constants.USDE_USD_MIN_THRESHOLD);
            assertEq(max, Constants.USDE_USD_MAX_THRESHOLD);
        }

        {
            assertEq(lovTokenContracts.sUsdeToUsdtOracle.description(), "sUSDe/USDT");
            assertEq(lovTokenContracts.sUsdeToUsdtOracle.decimals(), 18);
            assertEq(lovTokenContracts.sUsdeToUsdtOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.sUsdeToUsdtOracle.baseAsset()), Constants.SUSDE_ADDRESS);
            assertEq(address(lovTokenContracts.sUsdeToUsdtOracle.quoteAssetOracle()), address(lovTokenContracts.usdeToUsdtOracle));
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.SUSDE_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.USDT_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"dc5333039bcf15f1237133f74d5806675d83d9cf19cfd4cfdd9be674842651bf");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_sUSDe_USDT_invest_success() public {
        uint256 amount = 50_000e18;
        uint256 amountOut = investLovToken(alice, amount);
        uint256 expectedAmountOut = 49_950e18; // deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovToken.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.sUsdeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), amount);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), amount);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), amount);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), amount);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_sUSDe_USDT_rebalanceDown_success() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.2%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 155_628.853120e6); // USDT
        assertEq(reservesAmount, 150_535.684173820153362235e18);  // sUSDe

        // 1Inch implied sUSDe/USDT price
        uint256 expectedSwapPrice = 1.033833632033045929e18;
        assertEq(params.borrowAmount * 10**(18+18-6) / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.sUsdeToUsdtOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.037421934898461796e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.125) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.336954602629945952e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 150_015.001501035597271686e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 150_453.342335121593245678e18);
            uint256 expectedReserves = 200_563.246720347792567688e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount+1);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 50_548.245219312195296002e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50_109.904385226199322010e18);
        }
    }

    function test_lov_sUSDe_USDT_rebalanceUp_success() public {
        uint256 amount = 50_000e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.336954602629945952e18);
        }

        doRebalanceUp(1.36e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.359500722596497211e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 140_463.358585397943372549e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 140_873.789709917304435907e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 190_960.037495179404451563e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 190_960.037495179404451563e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 145_719.769246e6);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 50_496.678909781461079014e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50_086.247785262100015656e18);

            // No surplus USDT left over
            assertEq(externalContracts.usdtToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_sUSDe_USDT_fail_exit_staleOracle() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.sUsdeToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1711289195, 1.00292198e8));        
        lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.sUsdeToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1711289195, 1.00292198e8));        
        lovTokenContracts.lovToken.exitToToken(quoteData, bob);
    }

    function test_lov_sUSDe_USDT_success_exit() public {
        uint256 amount = 50_000e18;
        uint256 aliceBalance = investLovToken(alice, amount);
        assertEq(aliceBalance, 49_950e18);

        uint256 amountBack = exitLovToken(alice, aliceBalance/2, bob);
        assertEq(amountBack, 23_902.5e18);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), 24_975e18);
            assertEq(lovTokenContracts.lovToken.totalSupply(), 24_975e18);
            assertEq(externalContracts.sUsdeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 26_097.5e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 26_097.5e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 26_097.5e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 26_097.5e18);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_sUSDe_USDT_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.336785853995107381e18);

        uint256 maxExitAmount = 15_838.234315576427343812e18;
        assertEq(lovTokenContracts.lovToken.maxExit(address(externalContracts.sUsdeToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                maxExitAmount,
                address(externalContracts.sUsdeToken),
                0,
                0
            );

            lovTokenContracts.lovToken.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), Constants.USER_AL_FLOOR);
        }

        // Bob can't pull any - it will revert
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                10,
                address(externalContracts.sUsdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.28571e18, 1.285709999999999999e18, 1.28571e18));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_sUSDe_USDT_shutdown() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 401_075.863785767595520931e18);
        assertEq(liabilities, 300_030.003000941037745991e18);
        assertEq(ratio, 1.336785853995107381e18);

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        uint256 swapSlippageBps = 1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        params.repayAmount = lovTokenContracts.borrowLend.debtBalance() + 1_000e6;
        (params.withdrawCollateralAmount, params.swapData) = swapBorrowTokenToReserveTokenQuote(params.repayAmount);
        (params.repayAmount, params.swapData) = swapReserveTokenToBorrowTokenQuote(params.withdrawCollateralAmount);
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 99_123.471918058892509782e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of USDT which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.usdtToken.balanceOf(address(lovTokenContracts.borrowLend)), 246.860753e6);
    }

}

contract Origami_lov_sUSDe_USDT_IntegrationTest_PegControls is Origami_lov_sUSDe_USDT_IntegrationTestBase {

    function test_lov_sUSDe_USDT_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 50);

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1711289195, 1711289195, 1)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }

    function test_lov_sUSDe_USDT_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        doMint(externalContracts.sUsdeToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.sUsdeToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.sUsdeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1711289195, 1711289195, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function test_lov_sUSDe_USDT_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.sUsdeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 1.005e8+1, 1711289195, 1711289195, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1.00500001e18, 1.005e18));
        lovTokenContracts.lovToken.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.sUsdeToUsdtOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/USDT price, so includes the sUSDe/USDT ratio
        assertEq(spot, 1.037551141408727683e18);
        assertEq(hist, 1.034528270492912801e18);
        assertEq(baseAsset, address(externalContracts.sUsdeToken));
        assertEq(quoteAsset, address(externalContracts.usdtToken));

        (spot, hist, baseAsset, quoteAsset) = lovTokenContracts.usdeToUsdtOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/USDT price, so includes the sUSDe/USDT ratio
        assertEq(spot, 1.002921980000000000e18);
        assertEq(hist, 1e18);
        assertEq(baseAsset, address(externalContracts.usdeToken));
        assertEq(quoteAsset, address(externalContracts.usdtToken));
    }
}
