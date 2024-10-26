pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_wstETH_wETH_IntegrationTestBase } from "test/foundry/integration/lov-wstETH-wETH-morpho/Origami_lov_wstETH_wETH_IntegrationTestBase.t.sol";
import { Origami_lov_wstETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-wstETH-wETH-morpho/Origami_lov_wstETH_wETH_TestConstants.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { ErrorsLib as MorphoErrors } from "@morpho-org/morpho-blue/src/libraries/ErrorsLib.sol";

contract Origami_lov_wstETH_wETH_IntegrationTest is Origami_lov_wstETH_wETH_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_wstETH_wETH_morpho_initialization() public {
        {
            assertEq(address(lovTokenContracts.lovWstEth.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovWstEth.manager()), address(lovTokenContracts.lovWstEthManager));
            assertEq(lovTokenContracts.lovWstEth.annualPerformanceFeeBps(), Constants.PERFORMANCE_FEE_BPS);
        }

        {
            assertEq(address(lovTokenContracts.lovWstEthManager.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovWstEthManager.lovToken()), address(lovTokenContracts.lovWstEth));
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 0);

            (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = lovTokenContracts.lovWstEthManager.getFeeConfig();
            assertEq(minDepositFeeBps, Constants.MIN_DEPOSIT_FEE_BPS);
            assertEq(minExitFeeBps, Constants.MIN_EXIT_FEE_BPS);
            assertEq(feeLeverageFactor, Constants.FEE_LEVERAGE_FACTOR);

            (uint128 floor, uint128 ceiling) = lovTokenContracts.lovWstEthManager.userALRange();
            assertEq(floor, Constants.USER_AL_FLOOR);
            assertEq(ceiling, Constants.USER_AL_CEILING);
            (floor, ceiling) = lovTokenContracts.lovWstEthManager.rebalanceALRange();
            assertEq(floor, Constants.REBALANCE_AL_FLOOR);
            assertEq(ceiling, Constants.REBALANCE_AL_CEILING);

            assertEq(address(lovTokenContracts.lovWstEthManager.debtToken()), address(externalContracts.wethToken));
            assertEq(address(lovTokenContracts.lovWstEthManager.reserveToken()), address(externalContracts.wstEthToken));
            assertEq(address(lovTokenContracts.lovWstEthManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovWstEthManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.wstEthToEthOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.stEthToEthOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.stEthToEthOracle.description(), "stETH/ETH");
            assertEq(lovTokenContracts.stEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.stEthToEthOracle.precision(), 1e18);

            assertEq(lovTokenContracts.stEthToEthOracle.stableHistoricPrice(), Constants.STETH_ETH_HISTORIC_STABLE_PRICE);
            assertEq(address(lovTokenContracts.stEthToEthOracle.spotPriceOracle()), address(externalContracts.clStEthToEthOracle));
            assertEq(lovTokenContracts.stEthToEthOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.stEthToEthOracle.spotPricePrecisionScalar(), 1); // CL oracle is 18dp
            assertEq(lovTokenContracts.stEthToEthOracle.spotPriceStalenessThreshold(), Constants.STETH_ETH_STALENESS_THRESHOLD);
            (uint128 min, uint128 max) = lovTokenContracts.stEthToEthOracle.validSpotPriceRange();
            assertEq(min, Constants.STETH_ETH_MIN_THRESHOLD);
            assertEq(max, Constants.STETH_ETH_MAX_THRESHOLD);
        }

        {
            assertEq(lovTokenContracts.wstEthToEthOracle.description(), "wstETH/ETH");
            assertEq(lovTokenContracts.wstEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.wstEthToEthOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.wstEthToEthOracle.stEth()), Constants.STETH_ADDRESS);
            assertEq(address(lovTokenContracts.wstEthToEthOracle.stEthToEthOracle()), address(lovTokenContracts.stEthToEthOracle));
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.WSTETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.WETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"c54d7acf14de29e0e5527cabd7a576506870346a78a11a6762e2cca66322ec41");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_wstETH_wETH_morpho_invest_success() public {
        uint256 amount = 50e18;
        uint256 amountOut = investlovWstEth(alice, amount);
        uint256 expectedAmountOut = 49.11e18; // deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovWstEth.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovWstEth.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), amount);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), amount);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), amount);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), amount);
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_wstETH_wETH_morpho_rebalanceDown_success() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 20; // 0.2%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 463.795587257521068400e18); // wETH
        assertEq(reservesAmount, 399.842233817039274556e18);  // wstETH

        // 1Inch implied wstETH/wETH price
        uint256 expectedSwapPrice = 1.159946468960919510e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.wstEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.159488968143802671e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovWstEthManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.125) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124613557643720337e18);
            assertEq(lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 400e18 + 1);
            assertEq(lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 399.527530843806879843e18);
            uint256 expectedReserves = 449.845423057488135056e18;
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount+1);

            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49.845423057488135055e18);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.317892213681255213e18);
        }
    }

    function test_lov_wstETH_wETH_morpho_rebalanceUp_success() public {
        uint256 amount = 50e18;
        uint256 slippage = 20; // 0.2%
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124613557643720337e18);
        }

        doRebalanceUp(1.13e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.130018499020690030e18);
            assertEq(lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 383.420054312758958813e18);
            assertEq(lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 382.967168938937284996e18);
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 433.271754268935327779e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 433.271754268935327779e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 444.571323140741662311e18);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49.851699956176368966e18);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.304585329998042783e18);

            // No surplus weth left over
            assertEq(externalContracts.wethToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
        }
    }

    function test_lov_wstETH_wETH_morpho_fail_exit_staleOracle() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovWstEth.exitQuote(
            amount / 2,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.clStEthToEthOracle), 1710860351, 0.998818827109517200e18));        
        lovTokenContracts.lovWstEth.exitQuote(
            amount / 2,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.clStEthToEthOracle), 1710860351, 0.998818827109517200e18));        
        lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
    }

    function test_lov_wstETH_wETH_morpho_success_exit() public {
        uint256 amount = 50e18;
        uint256 aliceBalance = investlovWstEth(alice, amount);
        assertEq(aliceBalance, 49.11e18);

        uint256 amountBack = exitlovWstEth(alice, aliceBalance/2, bob);
        assertEq(amountBack, 24.875e18);

        {
            assertEq(lovTokenContracts.lovWstEth.balanceOf(alice), 24.555e18);
            assertEq(lovTokenContracts.lovWstEth.totalSupply(), 24.555e18);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 25.125e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 25.125e18);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 25.125e18);
            assertEq(lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 25.125e18);
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_wstETH_wETH_morpho_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        uint256 bobShares = investlovWstEth(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 20);
        assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124561120915994094e18);

        uint256 maxExitAmount = 9.865979612187328957e18;
        assertEq(lovTokenContracts.lovWstEth.maxExit(address(externalContracts.wstEthToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovWstEth.exitQuote(
                maxExitAmount,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            lovTokenContracts.lovWstEth.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), Constants.USER_AL_FLOOR);
        }

        // Bob can't pull any - it will revert
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovWstEth.exitQuote(
                10,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.112e18, 1.111999999999999999e18, 1.112e18));
            lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
        }

        // Pulling a chunky amount will cause the money market to revert since there isn't enough collateral.
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovWstEth.exitQuote(
                bobShares,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            vm.expectRevert(bytes(MorphoErrors.INSUFFICIENT_COLLATERAL));
            lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
        }
    }

    function test_lov_wstETH_wETH_morpho_shutdown() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        investlovWstEth(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovWstEth.assetsAndLiabilities();
        assertEq(assets, 899.648896732795275766e18);
        assertEq(liabilities, 800e18 + 1);
        assertEq(ratio, 1.124561120915994094e18);

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        uint256 swapSlippageBps = 1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        params.repayAmount = lovTokenContracts.borrowLend.debtBalance() + 1e18;
        (params.withdrawCollateralAmount, params.swapData) = swapWEthToWstEthQuote(params.repayAmount);
        (params.repayAmount, params.swapData) = swapWstEthToWEthQuote(params.withdrawCollateralAmount);
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovWstEthManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovWstEth.assetsAndLiabilities();
        assertEq(assets, 99.138018676719114768e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of wETH which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.wethToken.balanceOf(address(lovTokenContracts.borrowLend)), 0.835923856911664558e18);
    }

}

contract Origami_lov_wstETH_wETH_IntegrationTest_PegControls is Origami_lov_wstETH_wETH_IntegrationTestBase {

    function test_lov_wstETH_wETH_morpho_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 20);

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(954, 0.99e18-1, 1710860351, 1710860351, 954)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clStEthToEthOracle), 0.99e18-1, 0.99e18));
        lovTokenContracts.lovWstEthManager.rebalanceDown(params);
    }

    function test_lov_wstETH_wETH_morpho_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        doMint(externalContracts.wstEthToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.wstEthToken.approve(address(lovTokenContracts.lovWstEth), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovWstEth.investQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(954, 0.99e18-1, 1710860351, 1710860351, 954)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clStEthToEthOracle), 0.99e18-1, 0.99e18));
        lovTokenContracts.lovWstEth.investWithToken(quoteData);
    }

    function test_lov_wstETH_wETH_morpho_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovWstEth.exitQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(955, 1.01e18+1, 1710860351, 1710860351, 955)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.clStEthToEthOracle), 1.01e18+1, 1.01e18));
        lovTokenContracts.lovWstEth.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.wstEthToEthOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the wstETH/ETH price, so includes the wstETH/stETH ratio
        assertEq(spot, 1.159488968143802672e18);
        assertEq(hist, 1.160860144676336301e18);
        assertEq(baseAsset, address(externalContracts.wstEthToken));
        assertEq(quoteAsset, address(externalContracts.wethToken));
    }
}
