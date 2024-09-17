pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_USDe_DAI_IntegrationTestBase } from "test/foundry/integration/lov-USDe-DAI/Origami_lov_USDe_DAI_IntegrationTestBase.t.sol";
import { Origami_lov_USDe_DAI_TestConstants as Constants } from "test/foundry/deploys/lov-USDe-DAI/Origami_lov_USDe_DAI_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_USDe_DAI_IntegrationTest is Origami_lov_USDe_DAI_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_USDe_DAI_initialization() public {
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
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.usdeToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.usdeToDaiOracle));
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
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.USDE_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.DAI_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"c581c5f70bd1afa283eed57d1418c6432cbff1d862f94eaf58fdd4e46afbb67f");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_USDe_DAI_invest_success() public {
        uint256 amount = 50_000e18;
        uint256 amountOut = investLovToken(alice, amount);
        uint256 expectedAmountOut = 50_000e18; // no deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovToken.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.usdeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
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

    function test_lov_USDe_DAI_rebalanceDown_success() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.2%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 200_416.93e18); // DAI
        assertEq(reservesAmount, 199_960.950811050801985097e18);  // USDe

        // 1Inch implied USDe/DAI price
        uint256 expectedSwapPrice = 1.002280341172112482e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.usdeToDaiOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.00208465e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.25) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.249961659407333773e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200_000e18 + 1);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_416.930000000000000001e18);
            uint256 expectedReserves = 249_992.331881466754703843e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount + 1);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49_992.331881466754703842e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 49_575.401881466754703842e18);
        }
    }

    function test_lov_USDe_DAI_rebalanceUp_success() public {
        uint256 amount = 50_000e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.249961659407333773e18);
        }

        doRebalanceUp(1.30e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.299803698780951647e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 166_666.273035072026065688e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 167_013.713881154588964825e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 216_633.438153022603716646e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 216_633.438153022603716646e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 167_013.713881154588964825e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49_967.165117950577650958e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 49_619.724271868014751821e18);

            // No surplus DAI left over
            assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_USDe_DAI_fail_exit_staleOracle() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.usdeToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1712576123, 1.00208465e8));        
        lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.usdeToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1712576123, 1.00208465e8));        
        lovTokenContracts.lovToken.exitToToken(quoteData, bob);
    }

    function test_lov_USDe_DAI_success_exit() public {
        uint256 amount = 50_000e18;
        uint256 aliceBalance = investLovToken(alice, amount);
        assertEq(aliceBalance, amount);

        uint256 amountBack = exitLovToken(alice, aliceBalance/2, bob);
        assertEq(amountBack, 24_635e18);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), 25_000e18);
            assertEq(lovTokenContracts.lovToken.totalSupply(), 25_000e18);
            assertEq(externalContracts.usdeToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 25_365e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 25_365e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 25_365e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 25_365e18);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_USDe_DAI_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.249909261010427819e18);

        uint256 maxExitAmount = 21_200.818978355813236893e18;
        assertEq(lovTokenContracts.lovToken.maxExit(address(externalContracts.usdeToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                maxExitAmount,
                address(externalContracts.usdeToken),
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
                address(externalContracts.usdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.1977e18, 1.1977e18-1, 1.1977e18));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_USDe_DAI_shutdown() public {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 499_963.704404171127939369e18);
        assertEq(liabilities, 400_000e18 + 1);
        assertEq(ratio, 1.249909261010427819e18);

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
        assertEq(assets, 99_022.851962084933076856e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of DAI which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.daiToken.balanceOf(address(lovTokenContracts.borrowLend)), 686.906447832894814758e18);
    }

}

contract Origami_lov_USDe_DAI_IntegrationTest_PegControls is Origami_lov_USDe_DAI_IntegrationTestBase {

    function test_lov_USDe_DAI_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 50);

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1712576123, 1712576123, 1)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }

    function test_lov_USDe_DAI_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        doMint(externalContracts.usdeToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.usdeToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.usdeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1712576123, 1712576123, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 0.99499999e18, 0.995e18));
        lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function test_lov_USDe_DAI_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.usdeToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneUsdeToUsdOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 1.005e8+1, 1712576123, 1712576123, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneUsdeToUsdOracle), 1.00500001e18, 1.005e18));
        lovTokenContracts.lovToken.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.usdeToDaiOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the USDe/DAI price, so includes the USDe/DAI ratio
        assertEq(spot, 1.00208465e18);
        assertEq(hist, 1e18);
        assertEq(baseAsset, address(externalContracts.usdeToken));
        assertEq(quoteAsset, address(externalContracts.daiToken));

        (spot, hist, baseAsset, quoteAsset) = lovTokenContracts.usdeToDaiOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the USDe/DAI price, so includes the USDe/DAI ratio
        assertEq(spot, 1.00208465e18);
        assertEq(hist, 1e18);
        assertEq(baseAsset, address(externalContracts.usdeToken));
        assertEq(quoteAsset, address(externalContracts.daiToken));
    }
}
