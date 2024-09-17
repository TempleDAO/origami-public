pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTestBase } from "test/foundry/integration/lov-PT-sUSDe-Sep24-DAI/Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTestBase.t.sol";
import { Origami_lov_PT_sUSDe_Sep24_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-PT-sUSDe-Sep24-DAI/Origami_lov_PT_sUSDe_Sep24_DAI_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";

contract Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTest is Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_PT_sUSDe_Sep24_DAI_initialization() public {
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
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.ptSUSDeToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.ptSUsdeToDaiOracle));
        }
        
        {
            assertEq(lovTokenContracts.ptSUsdeToDaiOracle.description(), "PT-sUSDe-Sep24/DAI");
            assertEq(lovTokenContracts.ptSUsdeToDaiOracle.decimals(), 18);
            assertEq(lovTokenContracts.ptSUsdeToDaiOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.ptSUsdeToDaiOracle.baseAssetOracle()), address(lovTokenContracts.ptSUsdeToUSDeOracle));
            assertEq(address(lovTokenContracts.ptSUsdeToDaiOracle.quoteAssetOracle()), address(lovTokenContracts.usdeToDaiOracle));
            assertEq(address(lovTokenContracts.ptSUsdeToDaiOracle.priceCheckOracle()), address(0));
            assertEq(lovTokenContracts.ptSUsdeToDaiOracle.multiply(), true);
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.PT_SUSDE_SEP24_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.DAI_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"b5a5be93ba0c635e2106ba81fc883cfeb6971eaa22fa4fae1d539c73b9ee7bf6");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_PT_sUSDe_Sep24_DAI_invest_success() public {
        uint256 amount = 50_000e18;
        uint256 amountOut = investLovToken(alice, amount);
        uint256 expectedAmountOut = 49_600e18;
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovToken.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.ptSUSDeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
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

    function test_lov_PT_sUSDe_Sep24_DAI_rebalanceDown_success() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.2%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_LTV, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 200_020.002000200019680995e18); // DAI
        assertEq(reservesAmount, 206_413.920446048233250000e18);  // PT

        // 1Inch implied USDe/DAI price
        uint256 expectedSwapPrice = 0.969023802115519460e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.ptSUsdeToDaiOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 0.968926899735307909e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.25) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.242107501761333594e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 206_434.563902438477097710e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 206_270.877808028955550632e18);
            uint256 expectedReserves = 256_413.920446048233250000e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49_979.356543609756152290e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50_143.042638019277699368e18);
        }
    }

    function test_lov_PT_sUSDe_Sep24_DAI_rebalanceUp_success() public {
        uint256 amount = 50_000e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_LTV, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.236020566309157842e18);
        }

        doRebalanceUp(0.75e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.247791376154354412e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 197_392.659777620030594070e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 197_236.143189829160090899e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 246_304.858586684779994880e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 246_304.858586684779994880e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 191_259.057868835789756827e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 48_912.198809064749400810e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 49_068.715396855619903981e18);

            // No surplus DAI left over
            assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_PT_sUSDe_Sep24_DAI_fail_exit_staleOracle() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        
        doRebalanceDown(Constants.TARGET_LTV, 20, 50);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1720944275, 0.99920708e8));        
        lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1720944275, 0.99920708e8));        
        lovTokenContracts.lovToken.exitToToken(quoteData, bob);
    }

    function test_lov_PT_sUSDe_Sep24_DAI_success_exit() public {
        uint256 amount = 50_000e18;
        uint256 aliceBalance = investLovToken(alice, amount);
        assertEq(aliceBalance, 49_600e18);

        uint256 amountBack = exitLovToken(alice, aliceBalance/2, bob);
        assertEq(amountBack, 24_250e18);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), 24_800e18);
            assertEq(lovTokenContracts.lovToken.totalSupply(), 24_800e18);
            assertEq(externalContracts.ptSUSDeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 25_750e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 25_750e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 25_750e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 25_750e18);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_PT_sUSDe_Sep24_DAI_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_LTV, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.239747261483959323e18);

        uint256 maxExitAmount = 39_521.423683943855448340e18;
        assertEq(lovTokenContracts.lovToken.maxExit(address(externalContracts.ptSUSDeToken)), maxExitAmount);

        uint256 ptToDaiPrice = lovTokenContracts.ptSUsdeToDaiOracle.latestPrice(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                maxExitAmount,
                address(externalContracts.ptSUSDeToken),
                0,
                0
            );

            lovTokenContracts.lovToken.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), Constants.USER_AL_FLOOR * ptToDaiPrice / 1e18);
        }

        // Bob can't pull any - it will revert
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                10,
                address(externalContracts.ptSUSDeToken),
                0,
                0
            );

            uint256 expectedAL = 1.146724985836736910e18;
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, expectedAL, expectedAL-1, expectedAL));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_PT_sUSDe_Sep24_DAI_shutdown() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_LTV, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 512_827.840892096466500000e18);
        assertEq(liabilities, 413_655.151194485437374749e18);
        assertEq(ratio, 1.239747261483959323e18);

        uint256 marketPtToDaiPrice = lovTokenContracts.ptSUsdeToDaiOracle.latestPrice(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        params.repayAmount = lovTokenContracts.borrowLend.debtBalance();
        params.withdrawCollateralAmount = params.repayAmount * 1e18 / marketPtToDaiPrice;
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData(params.withdrawCollateralAmount));

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 99_172.689697611029125252e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a some residual DAI which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.borrowLend)), 12_853.547988072612366678e18);
    }
}

contract Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTest_PegControls is Origami_lov_PT_sUSDe_Sep24_DAI_IntegrationTestBase {

    function test_lov_PT_sUSDe_Sep24_DAI_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_LTV, 20, 50);

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1721006984, 1721006984, 1)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }

    function test_lov_PT_sUSDe_Sep24_DAI_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_LTV, 20, 50);

        amount = 1e18;
        deal(address(externalContracts.ptSUSDeToken), alice, amount, false);
        vm.startPrank(alice);
        externalContracts.ptSUSDeToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1721006984, 1721006984, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function test_lov_PT_sUSDe_Sep24_DAI_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_LTV, 20, 50);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.ptSUSDeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 1.005e8+1, 1721006984, 1721006984, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1.00500001e18, 1.005e18));
        lovTokenContracts.lovToken.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.ptSUsdeToDaiOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the USDe/DAI price, so includes the USDe/DAI ratio
        assertEq(spot, 0.968926899735307910e18);
        assertEq(hist, 0.969695790921845659e18);
        assertEq(baseAsset, address(externalContracts.ptSUSDeToken));
        assertEq(quoteAsset, address(externalContracts.daiToken));
    }
}
