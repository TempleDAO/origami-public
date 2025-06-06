pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_wstETH_wETH_IntegrationTestBase } from
    "test/foundry-integration/integration/lov-wstETH-wETH-eulerV2/Origami_lov_wstETH_wETH_EulerV2_IntegrationTestBase.t.sol";
import { Origami_lov_wstETH_wETH_EulerV2_TestConstants as Constants } from
    "test/foundry-integration/deploys/lov-wstETH-wETH-eulerV2/Origami_lov_wstETH_wETH_TestConstants.t.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from
    "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_wstETH_wETH_EulerV2_IntegrationTest is Origami_lov_wstETH_wETH_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_wstETH_wETH_eulerV2_initialization() public view {
        {
            assertEq(address(lovTokenContracts.lovWstEth.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovWstEth.manager()), address(lovTokenContracts.lovWstEthManager));
            assertEq(lovTokenContracts.lovWstEth.annualPerformanceFeeBps(), Constants.PERFORMANCE_FEE_BPS);
        }

        {
            assertEq(address(lovTokenContracts.lovWstEthManager.owner()), origamiMultisig);
            assertEq(address(lovTokenContracts.lovWstEthManager.lovToken()), address(lovTokenContracts.lovWstEth));
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 0);

            (uint64 minDepositFeeBps, uint64 minExitFeeBps, uint64 feeLeverageFactor) =
                lovTokenContracts.lovWstEthManager.getFeeConfig();
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
            assertEq(
                address(lovTokenContracts.lovWstEthManager.debtTokenToReserveTokenOracle()),
                address(lovTokenContracts.wstEthToEthOracle)
            );
        }

        {
            assertEq(address(lovTokenContracts.stEthToEthOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.stEthToEthOracle.description(), "stETH/ETH");
            assertEq(lovTokenContracts.stEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.stEthToEthOracle.precision(), 1e18);

            assertEq(
                lovTokenContracts.stEthToEthOracle.stableHistoricPrice(), Constants.STETH_ETH_HISTORIC_STABLE_PRICE
            );
            assertEq(
                address(lovTokenContracts.stEthToEthOracle.spotPriceOracle()),
                address(externalContracts.clStEthToEthOracle)
            );
            assertEq(lovTokenContracts.stEthToEthOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.stEthToEthOracle.spotPricePrecisionScalar(), 1); // CL oracle is 18dp
            assertEq(
                lovTokenContracts.stEthToEthOracle.spotPriceStalenessThreshold(),
                Constants.STETH_ETH_STALENESS_THRESHOLD
            );
            (uint128 min, uint128 max) = lovTokenContracts.stEthToEthOracle.validSpotPriceRange();
            assertEq(min, Constants.STETH_ETH_MIN_THRESHOLD);
            assertEq(max, Constants.STETH_ETH_MAX_THRESHOLD);
        }

        {
            assertEq(lovTokenContracts.wstEthToEthOracle.description(), "wstETH/ETH");
            assertEq(lovTokenContracts.wstEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.wstEthToEthOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.wstEthToEthOracle.stEth()), Constants.STETH_ADDRESS);
            assertEq(
                address(lovTokenContracts.wstEthToEthOracle.stEthToEthOracle()),
                address(lovTokenContracts.stEthToEthOracle)
            );
        }

        {
            // euler specifics
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.WSTETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.WETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.supplyVault()), Constants.SUPPLY_WSTETH_VAULT_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowVault()), Constants.BORROW_WETH_VAULT_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.eulerEVC()), Constants.EULER_EVC);

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }
    }

    function test_lov_wstETH_wETH_eulerv2_invest_success() public {
        uint256 amount = 50e18;
        uint256 amountOut = investlovWstEth(alice, amount);
        uint256 expectedAmountOut = 49.495e18 - 1; // deposit fees and rounding
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovWstEth.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovWstEth.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), amount-1);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), amount-1);
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), amount-1
            );
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                amount-1
            );
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(
                lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18
            );
        }
    }

    function test_lov_wstETH_wETH_eulerv2_rebalanceDown_success() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 20; // 0.2%
        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) =
            rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 479.898404112216919190e18); // wETH
        assertEq(reservesAmount, 399.972675386366359526e18); // wstETH

        // 1Inch implied wstETH/wETH price
        uint256 expectedSwapPrice = 1.199827972369971907e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(
            lovTokenContracts.wstEthToEthOracle.latestPrice(
                IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN
            ),
            1.199746010280542298e18
        );

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovWstEthManager.rebalanceDown(params);
        }

        {
            // Pretty close to the target (1.125) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124931688465915898e18);
            assertEq(lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 400e18 - 8);
            assertEq(
                lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                399.732263999999999687e18
            );
            uint256 expectedReserves = 449.972675386366359524e18;
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount);

            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE),
                49.972675386366359532e18
            );
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                50.240411386366359837e18
            );
        }
    }

    function test_lov_wstETH_wETH_eulerv2_rebalanceUp_success() public {
        uint256 amount = 50e18;
        uint256 slippage = 20; // 0.2%
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124931688465915898e18);
        }

        doRebalanceUp(1.13e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.129989237414167028e18);
            assertEq(
                lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE),
                384.408856548160301543e18
            );
            assertEq(
                lovTokenContracts.lovWstEthManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                384.151556324118355634e18
            );
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 434.377870666107586700e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 434.377870666107586700e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 461.192991960160638604e18);
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE),
                49.969014117947285157e18
            );
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                50.226314341989231066e18
            );

            // No surplus weth left over
            assertEq(externalContracts.wethToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
        }
    }

    function test_lov_wstETH_wETH_eulerv2_fail_exit_staleOracle() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) =
            lovTokenContracts.lovWstEth.exitQuote(amount / 2, address(externalContracts.wstEthToken), 0, 0);

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiOracle.StalePrice.selector,
                address(externalContracts.clStEthToEthOracle),
                1_745_343_587,
                0.99933066e18
            )
        );
        lovTokenContracts.lovWstEth.exitQuote(amount / 2, address(externalContracts.wstEthToken), 0, 0);

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiOracle.StalePrice.selector,
                address(externalContracts.clStEthToEthOracle),
                1_745_343_587,
                0.99933066e18
            )
        );
        lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
    }

    function test_lov_wstETH_wETH_eulerv2_success_exit() public {
        uint256 amount = 50e18;
        uint256 aliceBalance = investlovWstEth(alice, amount);
        assertEq(aliceBalance, 49.495e18 - 1); // fees and rounding

        uint256 amountBack = exitlovWstEth(alice, aliceBalance / 2, bob);
        assertEq(amountBack, 24.874999999999999998e18);

        {
            assertEq(lovTokenContracts.lovWstEth.balanceOf(alice), 24.7475e18);
            assertEq(lovTokenContracts.lovWstEth.totalSupply(), 24.7475e18);
            assertEq(externalContracts.wstEthToken.balanceOf(address(lovTokenContracts.lovWstEthManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 25.125e18 + 1);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovWstEthManager.reservesBalance(), 25.125e18 + 1);
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE),
                25.125e18 + 1
            );
            assertEq(
                lovTokenContracts.lovWstEthManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE),
                25.125e18 + 1
            );
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(
                lovTokenContracts.lovWstEthManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18
            );
        }
    }

    error E_AccountLiquidity();

    function test_lov_wstETH_wETH_eulerv2_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        uint256 bobShares = investlovWstEth(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 20);
        assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), 1.124991825644550644e18);

        uint256 maxExitAmount = 10.288642379216641195e18;
        assertEq(lovTokenContracts.lovWstEth.maxExit(address(externalContracts.wstEthToken)), maxExitAmount);

        {
            vm.startPrank(alice);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) =
                lovTokenContracts.lovWstEth.exitQuote(maxExitAmount, address(externalContracts.wstEthToken), 0, 0);

            lovTokenContracts.lovWstEth.exitToToken(quoteData, alice);
            assertEq(lovTokenContracts.lovWstEthManager.assetToLiabilityRatio(), Constants.USER_AL_FLOOR);
        }

        // Bob can't pull any - it will revert
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) =
                lovTokenContracts.lovWstEth.exitQuote(10, address(externalContracts.wstEthToken), 0, 0);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IOrigamiLovTokenManager.ALTooLow.selector, 1.112e18, 1.111999999999999999e18, 1.112e18
                )
            );
            lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
        }

        // Pulling a chunky amount will cause the money market to revert since there isn't enough collateral.
        {
            vm.startPrank(bob);
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) =
                lovTokenContracts.lovWstEth.exitQuote(bobShares, address(externalContracts.wstEthToken), 0, 0);

            vm.expectRevert(abi.encodeWithSelector(E_AccountLiquidity.selector));
            lovTokenContracts.lovWstEth.exitToToken(quoteData, bob);
        }
    }

    function test_lov_wstETH_wETH_eulerv2_shutdown() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        investlovWstEth(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovWstEth.assetsAndLiabilities();
        assertEq(assets, 899.993460515640515323e18);
        assertEq(liabilities, 800e18 - 8);
        assertEq(ratio, 1.124991825644550644e18);

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
        assertEq(assets, 99.221675043138326342e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of wETH which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.wethToken.balanceOf(address(lovTokenContracts.borrowLend)), 0.738945531588904036e18);
    }
}

contract Origami_lov_wstETH_wETH_IntegrationTest_PegControls is Origami_lov_wstETH_wETH_IntegrationTestBase {
    function test_lov_wstETH_wETH_eulerv2_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);

        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 20);

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(954, 0.99e18 - 1, 1_745_376_647, 1_745_376_647, 954)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiOracle.BelowMinValidRange.selector,
                address(externalContracts.clStEthToEthOracle),
                0.99e18 - 1,
                0.99e18
            )
        );
        lovTokenContracts.lovWstEthManager.rebalanceDown(params);
    }

    function test_lov_wstETH_wETH_eulerv2_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        doMint(externalContracts.wstEthToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.wstEthToken.approve(address(lovTokenContracts.lovWstEth), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData,) =
            lovTokenContracts.lovWstEth.investQuote(amount, address(externalContracts.wstEthToken), 0, 0);

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(954, 0.99e18 - 1, 1_745_376_647, 1_745_376_647, 954)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiOracle.BelowMinValidRange.selector,
                address(externalContracts.clStEthToEthOracle),
                0.99e18 - 1,
                0.99e18
            )
        );
        lovTokenContracts.lovWstEth.investWithToken(quoteData);
    }

    function test_lov_wstETH_wETH_eulerv2_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investlovWstEth(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 20);

        amount = 1e18;
        vm.startPrank(alice);
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) =
            lovTokenContracts.lovWstEth.exitQuote(amount, address(externalContracts.wstEthToken), 0, 0);

        vm.mockCall(
            address(externalContracts.clStEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(955, 1.01e18 + 1, 1_745_376_647, 1_745_376_647, 955)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiOracle.AboveMaxValidRange.selector,
                address(externalContracts.clStEthToEthOracle),
                1.01e18 + 1,
                1.01e18
            )
        );
        lovTokenContracts.lovWstEth.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public view {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts
            .wstEthToEthOracle
            .latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the wstETH/ETH price, so includes the wstETH/stETH ratio
        assertEq(spot, 1.199746010280542299e18);
        assertEq(hist, 1.200549586140529601e18);
        assertEq(baseAsset, address(externalContracts.wstEthToken));
        assertEq(quoteAsset, address(externalContracts.wethToken));
    }
}
