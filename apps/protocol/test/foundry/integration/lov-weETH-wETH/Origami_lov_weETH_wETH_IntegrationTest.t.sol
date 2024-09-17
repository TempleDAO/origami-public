pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { stdError } from "forge-std/StdError.sol";

import { Origami_lov_weETH_wETH_IntegrationTestBase } from "test/foundry/integration/lov-weETH-wETH/Origami_lov_weETH_wETH_IntegrationTestBase.t.sol";
import { Origami_lov_weETH_wETH_TestConstants as Constants } from "test/foundry/deploys/lov-weETH-wETH/Origami_lov_weETH_wETH_TestConstants.t.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";
import { Id as MorphoMarketId } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract Origami_lov_weETH_wETH_IntegrationTest is Origami_lov_weETH_wETH_IntegrationTestBase {
    using OrigamiMath for uint256;

    function test_lov_weETH_wETH_initialization() public {
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
            assertEq(address(lovTokenContracts.lovTokenManager.reserveToken()), address(externalContracts.weEthToken));
            assertEq(address(lovTokenContracts.lovTokenManager.borrowLend()), address(lovTokenContracts.borrowLend));
            assertEq(address(lovTokenContracts.lovTokenManager.debtTokenToReserveTokenOracle()), address(lovTokenContracts.weEthToEthOracle));
        }
        
        {
            assertEq(address(lovTokenContracts.weEthToEthOracle.owner()), origamiMultisig);
            assertEq(lovTokenContracts.weEthToEthOracle.description(), "weETH/wETH");
            assertEq(lovTokenContracts.weEthToEthOracle.decimals(), 18);
            assertEq(lovTokenContracts.weEthToEthOracle.precision(), 1e18);

            assertEq(address(lovTokenContracts.weEthToEthOracle.spotPriceOracle()), address(externalContracts.redstoneWeEthToEthOracle));
            assertEq(lovTokenContracts.weEthToEthOracle.spotPricePrecisionScaleDown(), false);
            assertEq(lovTokenContracts.weEthToEthOracle.spotPricePrecisionScalar(), 1e10); // Redstone oracle is 8dp
            assertEq(lovTokenContracts.weEthToEthOracle.spotPriceStalenessThreshold(), Constants.WEETH_ETH_STALENESS_THRESHOLD);
            assertEq(address(lovTokenContracts.weEthToEthOracle.etherfiLiquidityPool()), Constants.ETHERFI_LIQUIDITY_POOL);
            assertEq(lovTokenContracts.weEthToEthOracle.maxRelativeToleranceBps(), 30);
        }

        {
            assertEq(address(lovTokenContracts.borrowLend.morpho()), Constants.MORPHO);
            assertEq(address(lovTokenContracts.borrowLend.supplyToken()), Constants.WEETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.borrowToken()), Constants.WETH_ADDRESS);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketOracle()), Constants.MORPHO_MARKET_ORACLE);
            assertEq(address(lovTokenContracts.borrowLend.morphoMarketIrm()), Constants.MORPHO_MARKET_IRM);
            assertEq(lovTokenContracts.borrowLend.morphoMarketLltv(), Constants.MORPHO_MARKET_LLTV);
            assertEq(MorphoMarketId.unwrap(lovTokenContracts.borrowLend.marketId()), hex"698fe98247a40c5771537b5786b2f3f9d78eb487b4ce4d75533cd0e94d88a115");

            assertEq(address(lovTokenContracts.borrowLend.swapper()), address(lovTokenContracts.swapper));
        }

    }

    function test_lov_weETH_wETH_invest_success() public {
        uint256 amount = 15e18;
        uint256 amountOut = investLovToken(alice, amount);
        uint256 expectedAmountOut = 14.85e18; // 1% deposit fees
        assertEq(amountOut, expectedAmountOut);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), expectedAmountOut);
            assertEq(lovTokenContracts.lovToken.totalSupply(), expectedAmountOut);
            assertEq(externalContracts.weEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
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

    function test_lov_weETH_wETH_rebalanceDown_success() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);

        uint256 swapSlippage = 1; // 0.01%
        uint256 alSlippage = 50; // 0.5%
        (
            IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, 
            uint256 reservesAmount
        ) = rebalanceDownParams(Constants.TARGET_AL, swapSlippage, alSlippage);

        assertEq(params.borrowAmount, 62.1202824e18); // wETH
        assertEq(reservesAmount, 59.910958105153936831e18);  // weETH

        // 1Inch implied weETH/wETH price
        uint256 expectedSwapPrice = 1.036876797913468896e18;
        assertEq(params.borrowAmount * 1e18 / reservesAmount, expectedSwapPrice);

        // Oracle price is a little different. The 1inch swap data is more up to date than the oracle
        assertEq(lovTokenContracts.weEthToEthOracle.latestPrice(IOrigamiOracle.PriceType.SPOT_PRICE, OrigamiMath.Rounding.ROUND_DOWN), 1.03533804e18);

        {
            vm.startPrank(origamiMultisig);
            lovTokenContracts.lovTokenManager.rebalanceDown(params);
        }
        
        {
            // Pretty close to the target (1.25) - the swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.249200828390947448e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 60e18 + 1);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 59.934544697885388484e18);
            uint256 expectedReserves = 74.952049703456846936e18;
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), expectedReserves);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), params.borrowAmount + 1);

            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 14.952049703456846935e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 15.017505005571458452e18);
        }
    }

    function test_lov_weETH_wETH_rebalanceUp_success() public {
        uint256 amount = 15e18;
        uint256 slippage = 50; // 0.5%
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, slippage, slippage);

        {
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.249200828390947448e18);
        }

        doRebalanceUp(1.30e18, slippage, slippage);

        {
            // Pretty close to the target - swap prices and fx are slightly different to actual
            assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.299948134872783277e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 49.842154193318714379e18);
            assertEq(lovTokenContracts.lovTokenManager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 49.787780305639268916e18);
            assertEq(lovTokenContracts.lovTokenManager.reservesBalance(), 64.792215381646336716e18);
            assertEq(lovTokenContracts.borrowLend.suppliedBalance(), 64.792215381646336716e18);
            assertEq(lovTokenContracts.borrowLend.debtBalance(), 51.603478231888378840e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 14.950061188327622337e18);
            assertEq(lovTokenContracts.lovTokenManager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 15.004435076007067800e18);

            // No surplus wETH left over
            assertEq(externalContracts.wEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
        }
    }

    function test_lov_weETH_wETH_fail_exit_staleOracle() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.weEthToken),
            0,
            0
        );

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneWeEthToEthOracle), 1713437711, 1.03533804e8));
        lovTokenContracts.lovToken.exitQuote(
            amount / 2,
            address(externalContracts.weEthToken),
            0,
            0
        );

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.StalePrice.selector, address(externalContracts.redstoneWeEthToEthOracle), 1713437711, 1.03533804e8));
        lovTokenContracts.lovToken.exitToToken(quoteData, bob);
    }

    function test_lov_weETH_wETH_success_exit() public {
        uint256 amount = 15e18;
        uint256 aliceBalance = investLovToken(alice, amount);
        assertEq(aliceBalance, 14.85e18);

        uint256 amountBack = exitLovToken(alice, aliceBalance/2, bob);
        assertEq(amountBack, 7.425e18);

        {
            assertEq(lovTokenContracts.lovToken.balanceOf(alice), 7.425e18);
            assertEq(lovTokenContracts.lovToken.totalSupply(), 7.425e18);
            assertEq(externalContracts.weEthToken.balanceOf(address(lovTokenContracts.lovTokenManager)), 0);
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

    function test_lov_weETH_wETH_exit_fail_al_limit() public {
        vm.prank(origamiMultisig);

        uint256 amount = 15e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);
        
        doRebalanceDown(Constants.TARGET_AL, 20, 50);
        assertEq(lovTokenContracts.lovTokenManager.assetToLiabilityRatio(), 1.248533933349560379e18);

        uint256 maxExitAmount = 6.105375189753988443e18;
        assertEq(lovTokenContracts.lovToken.maxExit(address(externalContracts.weEthToken)), maxExitAmount);

        {
            vm.startPrank(alice);       
            (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
                maxExitAmount,
                address(externalContracts.weEthToken),
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
                address(externalContracts.weEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.1977e18, 1.1977e18-1, 1.1977e18));
            lovTokenContracts.lovToken.exitToToken(quoteData, bob);
        }
    }

    function test_lov_weETH_wETH_shutdown() public {
        uint256 amount = 15e18;
        investLovToken(alice, amount);
        investLovToken(bob, amount);

        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovTokenContracts.lovToken.assetsAndLiabilities();
        assertEq(assets, 149.824072001947245495e18);
        assertEq(liabilities, 120e18 + 1);
        assertEq(ratio, 1.248533933349560379e18);

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
        assertEq(assets, 29.035572391005375515e18);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);

        // No debt left, a tiny residual of wETH which can be reclaimed.
        assertEq(lovTokenContracts.borrowLend.debtBalance(), 0);
        assertEq(externalContracts.wEthToken.balanceOf(address(lovTokenContracts.borrowLend)), 0.755884881648801508e18);
    }

}

contract Origami_lov_weETH_wETH_IntegrationTest_PegControls is Origami_lov_weETH_wETH_IntegrationTestBase {

    function test_lov_weETH_wETH_rebalanceDown_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params,) = rebalanceDownParams(Constants.TARGET_AL, 20, 50);

        vm.mockCall(
            address(externalContracts.redstoneWeEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1713437711, 1713437711, 1)
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneWeEthToEthOracle), 0.99499999e18, 1.036468746248634283e18));
        lovTokenContracts.lovTokenManager.rebalanceDown(params);
    }

    function test_lov_weETH_wETH_invest_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        doMint(externalContracts.weEthToken, alice, amount);
        vm.startPrank(alice);
        externalContracts.weEthToken.approve(address(lovTokenContracts.lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovTokenContracts.lovToken.investQuote(
            amount,
            address(externalContracts.weEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneWeEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(1, 0.995e8-1, 1713437711, 1713437711, 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneWeEthToEthOracle), 0.99499999e18, 1.036468746248634283e18));
        lovTokenContracts.lovToken.investWithToken(quoteData);
    }

    function test_lov_weETH_wETH_exit_fail_peg_controls() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(Constants.TARGET_AL, 20, 50);

        amount = 1e18;
        vm.startPrank(alice);       
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = lovTokenContracts.lovToken.exitQuote(
            amount,
            address(externalContracts.weEthToken),
            0,
            0
        );

        vm.mockCall(
            address(externalContracts.redstoneWeEthToEthOracle),
            abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, 1.005e8+1, 1713437711, 1713437711, 0)
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiOracle.AboveMaxValidRange.selector, address(externalContracts.redstoneWeEthToEthOracle), 1.00500001e18, 1.036468746248634283e18));
        lovTokenContracts.lovToken.exitToToken(quoteData, alice);
    }

    function test_latestPrices() public {
        (uint256 spot, uint256 hist, address baseAsset, address quoteAsset) = lovTokenContracts.weEthToEthOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the weETH/wETH price, so includes the weETH/wETH ratio
        assertEq(spot, 1.03533804e18);
        assertEq(hist, 1.036468746248634283e18);
        assertEq(baseAsset, address(externalContracts.weEthToken));
        assertEq(quoteAsset, address(externalContracts.wEthToken));

        (spot, hist, baseAsset, quoteAsset) = lovTokenContracts.weEthToEthOracle.latestPrices(
            IOrigamiOracle.PriceType.SPOT_PRICE, 
            OrigamiMath.Rounding.ROUND_UP,
            IOrigamiOracle.PriceType.HISTORIC_PRICE, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        // Based off the weETH/wETH price, so includes the weETH/wETH ratio
        assertEq(spot, 1.03533804e18);
        assertEq(hist, 1.036468746248634283e18);
        assertEq(baseAsset, address(externalContracts.weEthToken));
        assertEq(quoteAsset, address(externalContracts.wEthToken));
    }
}
