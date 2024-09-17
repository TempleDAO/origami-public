pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_sUSDe_DAI_IntegrationTestBase } from "test/foundry/integration/lov-sUSDe-DAI/Origami_lov_sUSDe_DAI_IntegrationTestBase.t.sol";
import { Origami_lov_sUSDe_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-sUSDe-DAI/Origami_lov_sUSDe_DAI_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_sUSDe_DAI_IntegrationTest is Origami_lov_sUSDe_DAI_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_sUSDe_DAI_initialization() public {
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

            assertEq(address(lovTokenContracts.lovTokenManager.debtToken()), address(externalContracts.daiToken));
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.sUsdeToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.sUsdeToDaiOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.usdeToDaiOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.usdeToDaiOracle.description(), "USDe/DAI");
            assertEq(lovTokenContracts.usdeToDaiOracle.decimals(), 18);
            assertEq(lovTokenContracts.usdeToDaiOracle.precision(), 1e18);

            assertEq(lovTokenContracts.usdeToDaiOracle.stableHistoricPrice(), Constants.USDE_USD_HISTORIC_STABLE_PRICE);
            assertEq(address(lovTokenContracts.usdeToDaiOracle.spotPriceOracle()), address(externalContracts.redstoneUsdeToUsdOracle));
            assertEq(lovTokenContracts.usdeToDaiOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.usdeToDaiOracle.spotPricePrecisionScalar(), 1e10); // Redstone oracle is 8dp
            assertEq(lovTokenContracts.usdeToDaiOracle.spotPriceStalenessThreshold(), Constants.USDE_USD_STALENESS_THRESHOLD);
            (uint128 min, uint128 max) = lovTokenContracts.usdeToDaiOracle.validSpotPriceRange();
            assertEq(min, Constants.USDE_USD_MIN_THRESHOLD);
            assertEq(max, Constants.USDE_USD_MAX_THRESHOLD);
        }

        {
            assertEq(lovTokenContracts.sUsdeToDaiOracle.description(), "sUSDe/DAI");
            assertEq(lovTokenContracts.sUsdeToDaiOracle.decimals(), 18);
            assertEq(lovTokenContracts.sUsdeToDaiOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.sUsdeToDaiOracle.baseAsset()), Constants.SUSDE_ADDRESS);
            assertEq(address(lovTokenContracts.sUsdeToDaiOracle.quoteAssetOracle()), address(lovTokenContracts.usdeToDaiOracle));
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.SUSDE_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.DAI_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"42dcfb38bb98767afb6e38ccf90d59d0d3f0aa216beb3a234f12850323d17536");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_sUSDe_DAI_invest_success() public {
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

    function test_lov_sUSDe_DAI_rebalanceDown_success() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.2%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 129_677.741862307724500000e18); // DAI
        assertEq(reservesAmount, 125_532.703325744371208312e18);  // sUSDe

        // 1Inch implied sUSDe/DAI price
        uint256 expectedSwapPrice = 1.033019591124453102e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.sUsdeToDaiOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.037421934898461796e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.125) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.404527080867274361e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 125_000e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 125_365.247499999999982899e18);
            uint256 expectedReserves = 175_565.885108409295130538e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 50_565.885108409295130538e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50_200.637608409295147639e18);
        }
    }

    function test_lov_sUSDe_DAI_rebalanceUp_success() public {
        uint256 amount = 50_000e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.404527080867274361e18);
        }

        doRebalanceUp(1.45e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.449197396029937048e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 112_430.866305038768476660e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 112_759.387047764765641991e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 162_934.518682652173198400e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 162_934.518682652173198400e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 116_638.246864483591204295e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 50_503.652377613404721740e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50_175.131634887407556409e18);

            // No surplus DAI left over
            assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_sUSDe_DAI_fail_exit_staleOracle() public {
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

    function test_lov_sUSDe_DAI_success_exit() public {
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

    function test_lov_sUSDe_DAI_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.404500320477923523e18);

        uint256 maxExitAmount = 18_372.319687930915177716e18;
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

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.33334e18, 1.33334e18-1, 1.33334e18));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_sUSDe_DAI_shutdown() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 351_125.080119480880941281e18);
        assertEq(liabilities, 250_000e18);
        assertEq(ratio, 1.404500320477923523e18);

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        uint256 swapSlippageBps = 1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        params.repayAmount = lovTokenContracts.borrowLend.debtBalance() + 1_000e18;
        (params.withdrawCollateralAmount, params.swapData) = swapBorrowTokenToReserveTokenQuote(params.repayAmount);
        (params.repayAmount, params.swapData) = swapReserveTokenToBorrowTokenQuote(params.withdrawCollateralAmount);
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 99_131.521462460364417479e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of DAI which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.borrowLend)), 780.758050501611577443e18);
    }

}

contract Origami_lov_sUSDe_DAI_IntegrationTest_PegControls is Origami_lov_sUSDe_DAI_IntegrationTestBase {

    function test_lov_sUSDe_DAI_rebalanceDown_fail_peg_controls() public {
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

    function test_lov_sUSDe_DAI_invest_fail_peg_controls() public {
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

    function test_lov_sUSDe_DAI_exit_fail_peg_controls() public {
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
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.sUsdeToDaiOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/DAI price, so includes the sUSDe/DAI ratio
        assertEq(spot, 1.037551141408727683e18);
        assertEq(hist, 1.034528270492912801e18);
        assertEq(baseAsset, address(externalContracts.sUsdeToken));
        assertEq(quoteAsset, address(externalContracts.daiToken));

        (spot, hist, baseAsset, quoteAsset) = lovTokenContracts.usdeToDaiOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the sUSDe/DAI price, so includes the sUSDe/DAI ratio
        assertEq(spot, 1.002921980000000000e18);
        assertEq(hist, 1e18);
        assertEq(baseAsset, address(externalContracts.usdeToken));
        assertEq(quoteAsset, address(externalContracts.daiToken));
    }
}
