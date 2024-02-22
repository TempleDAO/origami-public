pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { OrigamiLovStEthIntegrationTestBase } from "test/foundry/integration/lovStEth/OrigamiLovStEthIntegrationTestBase.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiDexAggregatorSwapper } from "contracts/common/swappers/OrigamiDexAggregatorSwapper.sol";
import { OrigamiLovStEthTestConstants as Constants } from "test/foundry/deploys/lovStEth/OrigamiLovStEthTestConstants.t.sol";
import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";

contract OrigamiLovStEthIntegrationTest is OrigamiLovStEthIntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lovStEth_initialization() public {
        {
            assertEq(address(lovTokenContracts.lovStEth.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovStEth.manager()), address(lovTokenContracts.lovStEthManager));
            assertEq(lovTokenContracts.lovStEth.performanceFee(), Constants.LOV_ETH_PERFORMANCE_FEE_BPS);
            assertEq(lovTokenContracts.lovStEth.PERFORMANCE_FEE_FREQUENCY(), 7 days);
        }

        {
            assertEq(address(lovTokenContracts.lovStEthManager.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovStEthManager.lovToken()), address(lovTokenContracts.lovStEth));
            assertEq(lovTokenContracts.lovStEthManager.reservesBalance(), 0);

            (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) = lovTokenContracts.lovStEthManager.getFeeConfig();
            assertEq(minDepositFeeBps, Constants.LOV_ETH_MIN_DEPOSIT_FEE_BPS);
            assertEq(minExitFeeBps, Constants.LOV_ETH_MIN_EXIT_FEE_BPS);
            assertEq(feeLeverageFactor, Constants.LOV_ETH_FEE_LEVERAGE_FACTOR);

            assertEq(lovTokenContracts.lovStEthManager.redeemableReservesBufferBps(), 10_000);

            (uint128 floor, uint128 ceiling) = lovTokenContracts.lovStEthManager.userALRange();
            assertEq(floor, Constants.USER_AL_FLOOR);
            assertEq(ceiling, Constants.USER_AL_CEILING);
            (floor, ceiling) = lovTokenContracts.lovStEthManager.rebalanceALRange();
            assertEq(floor, Constants.REBALANCE_AL_FLOOR);
            assertEq(ceiling, Constants.REBALANCE_AL_CEILING);

            assertEq(address(lovTokenContracts.lovStEthManager.debtToken()), address(externalContracts.wethToken));
            assertEq(address(lovTokenContracts.lovStEthManager.reserveToken()), address(externalContracts.wstEthToken));
            assertEq(address(lovTokenContracts.lovStEthManager.flashLoanProvider()), address(lovTokenContracts.flashLoanProvider));
            assertEq(address(lovTokenContracts.lovStEthManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovStEthManager.swapper()), address(lovTokenContracts.swapper));
            assertEq(address(lovTokenContracts.lovStEthManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.wstEthToEthOracle));
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
            assertEq(OrigamiDexAggregatorSwapper(address(lovTokenContracts.swapper)).router(), Constants.ONE_INCH_ROUTER);
        }

        {
            assertEq(address(lovTokenContracts.flashLoanProvider.ADDRESSES_PROVIDER()), Constants.SPARK_POOL_ADDRESS_PROVIDER);
            assertEq(address(lovTokenContracts.flashLoanProvider.POOL()), Constants.SPARK_POOL);
            assertEq(lovTokenContracts.flashLoanProvider.REFERRAL_CODE(), 0);
        }

    }

    function test_lovStEth_invest_success() public {
        uint256 amount = 50e18;
        uint256 amountOut = investLovStEth(alice, amount);
        uint256 expectedAmountOut = 49.77e18; // deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovStEth.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovStEth.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovStEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), amount);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovStEthManager.reservesBalance(), amount);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), amount);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), amount);
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovStEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovStEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lovStEth_rebalanceDown_success() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 20; // 0.2%
        (
            IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.flashLoanAmount, 462.745060747016546400e18); // wETH
        assertEq(reservesAmount, 399.895276763268114781e18);  // wstETH

        // 1Inch implied wstETH/wETH price
        uint256 expectedSwapPrice = 1.157165607187089989e18;
        assertEq(params.flashLoanAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.wstEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.156862651867541366e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovStEthManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.125) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), 1.124738191908170286e18);
            assertEq(lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 400e18);
            assertEq(lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 399.879970737312799869e18);
            uint256 expectedReserves = 449.895276763268114786e18;
            assertEq(lovTokenContracts.lovStEthManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.flashLoanAmount);

            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49.895276763268114786e18);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.015306025955314917e18);
        }
    }
    
    function test_lovStEth_rebalanceUp_success() public {
        uint256 amount = 50e18;
        uint256 slippage = 20; // 0.2%
        investLovStEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), 1.124738191908170286e18);
        }

        doRebalanceUp(1.13e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), 1.130003678341790707e18);
            assertEq(lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 383.808571893864655879e18);
            assertEq(lovTokenContracts.lovStEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 383.693401244121036334e18);
            assertEq(lovTokenContracts.lovStEthManager.reservesBalance(), 433.705098019176690062e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 433.705098019176690062e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 444.013802290630169178e18);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 49.896526125312034183e18);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.011696775055653728e18);

            // No surplus weth left over
            assertEq(externalContracts.wethToken.balanceOf(address(lovTokenContracts.lovStEthManager)), 0);
        }
    }

    function test_lovStEth_fail_exit_staleOracle() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovStEth.exitQuote(
            amount / 2,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.clStEthToEthOracle), 1708008239, 0.999699926843282000e18));        
        lovTokenContracts.lovStEth.exitQuote(
            amount / 2,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.clStEthToEthOracle), 1708008239, 0.999699926843282000e18));        
        lovTokenContracts.lovStEth.exitToToken(quoteData, bob);
    }

    function test_lovStEth_success_exit() public {
        uint256 amount = 50e18;
        uint256 aliceBalance = investLovStEth(alice, amount);
        assertEq(aliceBalance, 49.77e18);

        uint256 amountBack = exitLovStEth(alice, aliceBalance/2, bob);
        assertEq(amountBack, 24.875e18);

        {
            assertEq(lovTokenContracts.lovStEth.balanceOf(alice), 24.885e18);
            assertEq(lovTokenContracts.lovStEth.totalSupply(), 24.885e18);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovStEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 25.125e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovStEthManager.reservesBalance(), 25.125e18);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 25.125e18);
            assertEq(lovTokenContracts.lovStEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 25.125e18);
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovStEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovStEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lovStEth_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        uint256 bobShares = investLovStEth(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 20);
        assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), 1.124704629298594172e18);

        uint256 maxExitAmount = 10.168431087280561602e18;
        assertEq(lovTokenContracts.lovStEth.maxExit(address(externalContracts.wstEthToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovStEth.exitQuote(
                maxExitAmount,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            lovTokenContracts.lovStEth.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovStEthManager.assetToLiabilityRatio(), Constants.USER_AL_FLOOR);
        }

        // Bob can't pull any - it will revert
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovStEth.exitQuote(
                10,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.112e18, 1.111999999999999999e18, 1.112e18));
            lovTokenContracts.lovStEth.exitToToken(quoteData, bob);
        }

        // Pulling a chunky amount will cause Aave to revert since there isn't enough collateral.
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovStEth.exitQuote(
                bobShares,
                address(externalContracts.wstEthToken),
                0,
                0
            );

            vm.expectRevert(bytes(AaveErrors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
            lovTokenContracts.lovStEth.exitToToken(quoteData, bob);
        }
    }

    function test_lovStEth_shutdown() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        investLovStEth(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovStEth.assetsAndLiabilities();
        assertEq(assets, 899.763703438875338173e18);
        assertEq(liabilities, 800e18);
        assertEq(ratio, 1.124704629298594172e18);

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        uint256 swapSlippageBps = 1;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        params.flashLoanAmount = lovTokenContracts.borrowLend.debtBalance() + 1e18;
        (params.collateralToWithdraw, params.swapData) = swapWEthToWstEthQuote(params.flashLoanAmount);
        (params.flashLoanAmount, params.swapData) = swapWstEthToWEthQuote(params.collateralToWithdraw);
        params.flashLoanAmount = params.flashLoanAmount.subtractBps(swapSlippageBps);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovStEthManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovStEth.assetsAndLiabilities();
        assertEq(assets, 99.178496203655111985e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        assertEq(lovTokenContracts.borrowLend.aaveDebtToken().balanceOf(address(lovTokenContracts.lovStEthManager)), 0);
    }

}

contract OrigamiLovStEthIntegrationTest_PegControls is OrigamiLovStEthIntegrationTestBase {

    function test_lovStEth_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 20);

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(921, 0.99e18-1, 1708008239, 1708008239, 921)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clStEthToEthOracle), 0.99e18-1, 0.99e18));
        lovTokenContracts.lovStEthManager.rebalanceDown(params);
    }

    function test_lovStEth_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        doMint(externalContracts.wstEthToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.wstEthToken.approve(address(lovTokenContracts.lovStEth), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovStEth.investQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(921, 0.99e18-1, 1708008239, 1708008239, 921)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.BelowMinValidRange.selector, address(externalContracts.clStEthToEthOracle), 0.99e18-1, 0.99e18));
        lovTokenContracts.lovStEth.investWithToken(quoteData);
    }

    function test_lovStEth_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovStEth.exitQuote(
            amount,
            address(externalContracts.wstEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(921, 1.01e18+1, 1708008239, 1708008239, 921)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.clStEthToEthOracle), 1.01e18+1, 1.01e18));
        lovTokenContracts.lovStEth.exitToToken(quoteData, alice);
    }
}
