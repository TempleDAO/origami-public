pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_ezETH_wETH_IntegrationTestBase } from "test/foundry/integration/lov-ezETH-wETH/Origami_lov_ezETH_wETH_IntegrationTestBase.t.sol";
import { Origami_lov_ezETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-ezETH-wETH/Origami_lov_ezETH_wETH_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_ezETH_wETH_IntegrationTest is Origami_lov_ezETH_wETH_IntegrationTestBase {
    using OrigamiMath for uint256;
    error OraclePriceExpired(); // From Renzo

    function test_lov_ezETH_wETH_initialization() public {
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

            assertEq(address(lovTokenContracts.lovTokenManager.debtToken()), address(externalContracts.wEthToken));
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.ezEthToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.ezEthToEthOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.ezEthToEthOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.ezEthToEthOracle.description(), "ezETH/wETH");
            assertEq(lovTokenContracts.ezEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.ezEthToEthOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.ezEthToEthOracle.spotPriceOracle()), address(externalContracts.redstoneEzEthToEthOracle));
            assertEq(lovTokenContracts.ezEthToEthOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.ezEthToEthOracle.spotPricePrecisionScalar(), 1e10); // Redstone oracle is 8dp
            assertEq(lovTokenContracts.ezEthToEthOracle.spotPriceStalenessThreshold(), Constants.EZETH_ETH_STALENESS_THRESHOLD);
            assertEq(address(lovTokenContracts.ezEthToEthOracle.renzoRestakeManager()), Constants.RENZO_RESTAKE_MANAGER);
            assertEq(lovTokenContracts.ezEthToEthOracle.maxRelativeToleranceBps(), 30);
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.EZETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.WETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"49bb2d114be9041a787432952927f6f144f05ad3e83196a7d062f374ee11d0ee");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_ezETH_wETH_invest_success() public {
        uint256 amount = 15e18;
        uint256 amountOut = investLovToken(alice, amount);
        uint256 expectedAmountOut = 14.85e18; // 1% deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovToken.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.ezEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
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

    function test_lov_ezETH_wETH_rebalanceDown_success() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.5%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 60.4797324e18); // wETH
        assertEq(reservesAmount, 60.040669200512086450e18);  // ezETH

        // 1Inch implied ezETH/wETH price
        uint256 expectedSwapPrice = 1.007312763254213841e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.ezEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.00799554e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.25) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.250677820008534774e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 60e18 + 1);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 59.987785874225480768e18);
            uint256 expectedReserves = 75.040669200512086450e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount + 1);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 15.040669200512086449e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 15.052883326286605682e18);
        }
    }

    function test_lov_ezETH_wETH_rebalanceUp_success() public {
        uint256 amount = 15e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.250677820008534774e18);
        }

        doRebalanceUp(1.30e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.299778677507019972e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 50.144100938189941257e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.133893165594787259e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 65.176233202219041276e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 65.176233202219041276e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 50.545030103005276459e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 15.032132264029100019e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 15.042340036624254017e18);

            // No surplus wETH left over
            assertEq(externalContracts.wEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_ezETH_wETH_fail_exit_staleOracle() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.ezEthToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(OraclePriceExpired.selector));
        lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.ezEthToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OraclePriceExpired.selector));
        lovTokenContracts.lovToken.exitToToken(quoteData, bob);
    }

    function test_lov_ezETH_wETH_success_exit() public {
        uint256 amount = 15e18;
        uint256 aliceBalance = investLovToken(alice, amount);
        assertEq(aliceBalance, 14.85e18);

        uint256 amountBack = exitLovToken(alice, aliceBalance/2, bob);
        assertEq(amountBack, 7.425e18);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), 7.425e18);
            assertEq(lovTokenContracts.lovToken.totalSupply(), 7.425e18);
            assertEq(externalContracts.ezEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 7.575e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 7.575e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 7.575e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 7.575e18);
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), type(uint128).max);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(lovTokenContracts.lovTokenManager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
        }
    }

    function test_lov_ezETH_wETH_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 15e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.250665124647932023e18);

        uint256 maxExitAmount = 6.307255438750618220e18;
        assertEq(lovTokenContracts.lovToken.maxExit(address(externalContracts.ezEthToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                maxExitAmount,
                address(externalContracts.ezEthToken),
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
                address(externalContracts.ezEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.1977e18, 1.1977e18-1, 1.1977e18));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_ezETH_wETH_shutdown() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 150.079814957751842817e18);
        assertEq(liabilities, 120e18 + 1);
        assertEq(ratio, 1.250665124647932023e18);

        // Repay the full balance that was borrowed. RebalanceUp for current debt balance + 1 eth extra
        uint256 swapSlippageBps = 1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        params.repayAmount = lovTokenContracts.borrowLend.debtBalance() + 1e18;
        (params.withdrawCollateralAmount, params.swapData) = swapBorrowTokenToReserveTokenQuote(params.repayAmount);
        (params.repayAmount, params.swapData) = swapReserveTokenToBorrowTokenQuote(params.withdrawCollateralAmount);
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;

        vm.startPrank(origamiMultisig);

        lovTokenContracts.lovTokenManager.forceRebalanceUp(params);

        (assets, liabilities, ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 29.054498457464591610e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of wETH which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.wEthToken.balanceOf(address(lovTokenContracts.borrowLend)), 0.908253019570339394e18);
    }

}

contract Origami_lov_ezETH_wETH_IntegrationTest_PegControls is Origami_lov_ezETH_wETH_IntegrationTestBase {

    function test_lov_ezETH_wETH_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 50);

        vm.mockCall(
            address(externalContracts.redstoneEzEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1713480767, 1713480767, 1)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneEzEthToEthOracle), 0.99499999e18, 1.008165423786972186e18));
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }

    function test_lov_ezETH_wETH_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        doMint(externalContracts.ezEthToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.ezEthToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.ezEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneEzEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1713480767, 1713480767, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneEzEthToEthOracle), 0.99499999e18, 1.008164413697743058e18));
        lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function test_lov_ezETH_wETH_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.ezEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneEzEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 1.005e8+1, 1713480767, 1713480767, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneEzEthToEthOracle), 1.00500001e18, 1.008165423786972186e18));
        lovTokenContracts.lovToken.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.ezEthToEthOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the ezETH/wETH price, so includes the ezETH/wETH ratio
        assertEq(spot, 1.00799554e18);
        assertEq(hist, 1.008215930829203042e18);
        assertEq(baseAsset, address(externalContracts.ezEthToken));
        assertEq(quoteAsset, address(externalContracts.wEthToken));

        (spot, hist, baseAsset, quoteAsset) = lovTokenContracts.ezEthToEthOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the ezETH/wETH price, so includes the ezETH/wETH ratio
        assertEq(spot, 1.007995540000000000e18);
        assertEq(hist, 1.008215930829203042e18);
        assertEq(baseAsset, address(externalContracts.ezEthToken));
        assertEq(quoteAsset, address(externalContracts.wEthToken));
    }
}
