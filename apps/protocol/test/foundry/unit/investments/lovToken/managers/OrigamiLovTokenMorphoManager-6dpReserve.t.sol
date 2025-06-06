pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { ErrorsLib as MorphoErrors } from "@morpho-org/morpho-blue/src/libraries/ErrorsLib.sol";

import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";
import { OrigamiPendlePtToAssetOracle } from "contracts/common/oracle/OrigamiPendlePtToAssetOracle.sol";

contract OrigamiLovTokenMorphoManagerTestBase_6dpReserve is OrigamiTest {
    using OrigamiMath for uint256;

    IERC20 internal lbtcToken;
    IERC20 internal ptLbtcToken;
    OrigamiLovToken internal lovToken;
    OrigamiLovTokenMorphoManager internal manager;
    TokenPrices internal tokenPrices;
    DummyLovTokenSwapper internal swapper;
    OrigamiMorphoBorrowAndLend internal borrowLend;

    OrigamiPendlePtToAssetOracle ptLbtcToLbtcOracle;

    Range.Data internal userALRange;
    Range.Data internal rebalanceALRange;

    address public constant PT_LBTC_MAR_2025_ADDRESS = 0xEc5a52C685CC3Ad79a6a347aBACe330d69e0b1eD;
    address public constant PT_LBTC_MAR_2025_MARKET = 0x70B70Ac0445C3eF04E314DFdA6caafd825428221;
    address public constant LBTC_ADDRESS = 0x8236a87084f8B84306f72007F36F2618A5634494;

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_ORACLE = 0x5283B67Fadc6Bb299C0DC90f97191132ace413a5;
    address internal constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 internal constant MORPHO_MARKET_LLTV = 0.915e18; // 91.5%
    uint96 internal constant MAX_SAFE_LLTV = 0.9e18; // 90%

    uint16 internal constant MIN_DEPOSIT_FEE_BPS = 0;
    uint16 internal constant MIN_EXIT_FEE_BPS = 200;
    uint24 internal constant FEE_LEVERAGE_FACTOR = 0;
    uint48 internal constant PERFORMANCE_FEE_BPS = 200;

    address internal constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
    uint32 internal constant PENDLE_TWAP_DURATION = 15*60;

    uint128 internal TARGET_AL = 1.25e18;
    uint128 internal USER_AL_FLOOR = 1.1429e18;
    uint128 internal USER_AL_CEILING = 1.4286e18;
    uint128 internal REBALANCE_AL_FLOOR = 1.1765e18;
    uint128 internal REBALANCE_AL_CEILING = 1.3334e18;

    function setUp() public virtual {
        fork("mainnet", 21441858);
        vm.warp(1734675101);

        lbtcToken = IERC20(LBTC_ADDRESS);
        ptLbtcToken = IERC20(PT_LBTC_MAR_2025_ADDRESS);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(
            origamiMultisig, 
            "Origami lov-PT-LBTC-5x", 
            "lov-PT-LBTC-5x", 
            PERFORMANCE_FEE_BPS, 
            feeCollector, 
            address(tokenPrices),
            type(uint256).max
        );

        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(ptLbtcToken),
            address(lbtcToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            MORPHO_MARKET_LLTV,
            MAX_SAFE_LLTV
        );
        manager = new OrigamiLovTokenMorphoManager(
            origamiMultisig, 
            address(ptLbtcToken), 
            address(lbtcToken),
            address(ptLbtcToken),
            address(lovToken),
            address(borrowLend)
        );
        swapper = new DummyLovTokenSwapper();

        ptLbtcToLbtcOracle = new OrigamiPendlePtToAssetOracle(
            IOrigamiOracle.BaseOracleParams(
                "PT-LBTC-Mar25/LBTC",
                address(ptLbtcToken),
                IERC20Metadata(address(ptLbtcToken)).decimals(),
                address(lbtcToken),
                IERC20Metadata(address(lbtcToken)).decimals()
            ),
            PENDLE_ORACLE,
            PT_LBTC_MAR_2025_MARKET,
            PENDLE_TWAP_DURATION
        );

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(address(manager));
        borrowLend.setSwapper(address(swapper));

        userALRange = Range.Data(USER_AL_FLOOR, USER_AL_CEILING);
        rebalanceALRange = Range.Data(REBALANCE_AL_FLOOR, REBALANCE_AL_CEILING);

        manager.setOracles(address(ptLbtcToLbtcOracle), address(ptLbtcToLbtcOracle));
        manager.setUserALRange(userALRange.floor, userALRange.ceiling);
        manager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        manager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);

        lovToken.setManager(address(manager));

        vm.stopPrank();
    }

    function convertAL(uint128 al) internal virtual view returns (uint128) {
        return al;
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        deal(address(ptLbtcToken), account, amount);
        vm.startPrank(account);
        ptLbtcToken.approve(address(lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            amount,
            address(ptLbtcToken),
            0,
            0
        );

        amountOut = lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            amount,
            address(ptLbtcToken),
            0,
            0
        );

        amountOut = lovToken.exitToToken(quoteData, recipient);
    }

    // Increase liabilities to lower A/L
    function doRebalanceDown(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual returns (uint256 reservesAmount) {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, alSlippageBps);

        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = LovTokenHelpers.solveRebalanceDownAmount(manager, targetAL);
        params.borrowAmount = ptLbtcToLbtcOracle.convertAmount(
            address(ptLbtcToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));
        params.supplyAmount = reservesAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.minNewAL = convertAL(params.minNewAL);
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
        params.maxNewAL = convertAL(params.maxNewAL);
        params.supplyCollateralSurplusThreshold = 0;
    }

    function doRebalanceDownFor(
        uint256 reservesAmount, 
        uint256 slippageBps
    ) internal {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        params.borrowAmount = ptLbtcToLbtcOracle.convertAmount(
            address(ptLbtcToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));
        params.supplyAmount = reservesAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;
        params.supplyCollateralSurplusThreshold = 0;

        deal(address(ptLbtcToken), address(swapper), reservesAmount);
        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual {
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, slippageBps, alSlippageBps);
        vm.startPrank(origamiMultisig);
        manager.rebalanceUp(params);
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params
    ) {
        // ideal reserves amount to remove
        params.withdrawCollateralAmount = LovTokenHelpers.solveRebalanceUpAmount(manager, targetAL);

        params.repayAmount = ptLbtcToLbtcOracle.convertAmount(
            address(ptLbtcToken),
            params.withdrawCollateralAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );

        // The amount we'll get for swapping params.withdrawCollateralAmount
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.repayAmount
        }));

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [wstETH] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.repayAmount = params.repayAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = 0;

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.minNewAL = convertAL(params.minNewAL);
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
        params.maxNewAL = convertAL(params.maxNewAL);
    }
}

contract OrigamiLovTokenMorphoManagerTestAdmin_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    function test_initialization() public virtual {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.lovToken()), address(lovToken));

        assertEq(manager.baseToken(), address(ptLbtcToken));
        assertEq(manager.reserveToken(), address(ptLbtcToken));
        assertEq(manager.debtToken(), address(lbtcToken));
        assertEq(manager.dynamicFeeOracleBaseToken(), address(ptLbtcToken));
        assertEq(address(manager.borrowLend()), address(borrowLend));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(ptLbtcToLbtcOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(ptLbtcToLbtcOracle));

        (uint64 minDepositFee, uint64 minExitFee, uint64 feeLeverageFactor) = manager.getFeeConfig();
        assertEq(minDepositFee, MIN_DEPOSIT_FEE_BPS);
        assertEq(minExitFee, MIN_EXIT_FEE_BPS);
        assertEq(feeLeverageFactor, FEE_LEVERAGE_FACTOR);

        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, USER_AL_FLOOR);
        assertEq(ceiling, USER_AL_CEILING);

        (floor, ceiling) = manager.rebalanceALRange();
        assertEq(floor, REBALANCE_AL_FLOOR);
        assertEq(ceiling, REBALANCE_AL_CEILING);

        assertEq(manager.areInvestmentsPaused(), false);
        assertEq(manager.areExitsPaused(), false);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.reservesBalance(), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), type(uint128).max);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.HISTORIC_PRICE), type(uint128).max);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        address[] memory tokens = manager.acceptedInvestTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(ptLbtcToken));

        tokens = manager.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(ptLbtcToken));
    }
}

contract OrigamiLovTokenMorphoManagerTestViews_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    function test_reservesBalance() public virtual {
        uint256 amount = 0.01e8;

        investLovToken(alice, amount);
        uint256 expectedReserves = amount;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        doRebalanceDown(TARGET_AL, 0, 5);
        expectedReserves = 0.05000000e8;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.249999687500078124e18);

        doRebalanceUp(rebalanceALRange.ceiling-0.00001e18, 0, 5);
        expectedReserves = 0.03999484e8;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.333390231989824919e18);

        uint256 exitAmount = 0.005e18;
        exitLovToken(alice, exitAmount, bob);
        expectedReserves = 0.03509485e8;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.170029188343999053e18);
        
        assertEq(ptLbtcToken.balanceOf(bob), 0.00489999e8);
    }

    function test_liabilities_success() public virtual {
        uint256 amount = 0.01e8;

        investLovToken(alice, amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        doRebalanceDown(TARGET_AL, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.04e8 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.04e8 + 1);

        doRebalanceUp(rebalanceALRange.ceiling-0.00001e18, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.02999485e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.02999485e8);

        // Exits don't affect liabilities
        uint256 exitAmount = 0.005e18;
        exitLovToken(alice, exitAmount, bob);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.02999485e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.02999485e8);
    }

    function test_liabilities_zeroDebt() public virtual {
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_liabilities_withDebt_isPricingToken() public virtual {
        uint256 amount = 0.01e8;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.04e8 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.04e8 + 1);
    }

    function test_liabilities_withDebt_notPricingToken() public virtual {
        // Setup the oracle so it's the inverse (LBTC/PT)
        vm.startPrank(origamiMultisig);

        {
            // Hack to get the reciprocal LBTC/PT
            DummyOracle clOne = new DummyOracle(
                DummyOracle.Answer({
                    roundId: 1,
                    answer: 1e18,
                    startedAt: 1706225627,
                    updatedAtLag: 1,
                    answeredInRound: 1
                }),
                18
            );
            OrigamiStableChainlinkOracle oOne = new OrigamiStableChainlinkOracle(
                origamiMultisig, 
                IOrigamiOracle.BaseOracleParams(
                    "ONE/ONE", 
                    address(lbtcToken),
                    18,
                    address(lbtcToken),
                    18
                ),
                1e18, 
                address(clOne), 
                365 days, 
                Range.Data(1e18, 1e18),
                false,
                true
            );

            OrigamiCrossRateOracle lbtcToPt = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "LBTC/PT_LBTC",
                    address(lbtcToken),
                    8,
                    address(ptLbtcToken),
                    8
                ),
                address(oOne), 
                address(ptLbtcToLbtcOracle),
                address(0)
            );

            manager.setOracles(address(lbtcToPt), address(lbtcToPt));
        }

        uint256 amount = 0.01e8;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.04e8 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.04e8 + 1);
    }

    function test_getDynamicFeesBps() public virtual {
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 0);
        assertEq(exitFee, 200);
    }
}

contract OrigamiLovTokenMorphoManagerTestInvest_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    using OrigamiMath for uint256;
    
    function test_maxInvest_fail_badAsset() public virtual {
        assertEq(manager.maxInvest(alice), 0);
    }

    function test_maxInvest_reserveToken() public virtual {
        vm.startPrank(origamiMultisig);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxInvest(address(ptLbtcToken)), expectedAvailable);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 1e8);
            assertEq(manager.reservesBalance(), 1e8);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.maxInvest(address(ptLbtcToken)), expectedAvailable);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(0.0001e8, 0);
            uint256 expectedReserves = 1e8 + 0.0001e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.0001e8 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.0001e8 + 1);
            assertEq(manager.maxInvest(address(ptLbtcToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 0.71439997e8;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 4.99999992e8;
            uint256 expectedLiabilities = 3.99999993e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxInvest(address(ptLbtcToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e2;
            deal(address(ptLbtcToken), alice, investAmount);
            vm.startPrank(alice);
            ptLbtcToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(ptLbtcToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.250000001875000032e18, 1.428600247500504331e18, 1.4286e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(ptLbtcToken)), 0);
            exitLovToken(alice, amountOut, alice);
        }
    }

    function test_maxInvest_reserveToken_withMaxTotalSupply() public virtual {
        vm.startPrank(origamiMultisig);
        uint256 maxTotalSupply = 2e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            // share price = 1
            assertEq(manager.maxInvest(address(ptLbtcToken)), 2e8);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 1e8);
            assertEq(manager.reservesBalance(), 1e8);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            // share price > 1
            assertEq(manager.maxInvest(address(ptLbtcToken)), 1e8);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(0.0001e8, 0);
            uint256 expectedReserves = 1e8 + 0.0001e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.0001e8 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.0001e8 + 1);
            assertEq(manager.maxInvest(address(ptLbtcToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 0.71439997e8;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 4.99999992e8;
            uint256 expectedLiabilities = 3.99999993e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxInvest(address(ptLbtcToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e2;
            deal(address(ptLbtcToken), alice, investAmount);
            vm.startPrank(alice);
            ptLbtcToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(ptLbtcToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.250000001875000032e18, 1.428600247500504331e18, 1.4286e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(ptLbtcToken)), 0);
            exitLovToken(alice, amountOut, alice);
        }
    }

    function test_investQuote_badToken_gives0() public virtual {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            100,
            alice,
            100,
            123
        );

        assertEq(quoteData.fromToken, address(alice));
        assertEq(quoteData.fromTokenAmount, 100);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 0);
        assertEq(quoteData.minInvestmentAmount, 0);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 0);
    }

    function test_investQuote_reserveToken() public virtual {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            1e8,
            address(ptLbtcToken),
            100,
            123
        );

        assertEq(quoteData.fromToken, address(ptLbtcToken));
        assertEq(quoteData.fromTokenAmount, 1e8);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 1e18);
        assertEq(quoteData.minInvestmentAmount, 0.99e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 0);
    }

    function test_investWithToken_fail_badToken() public virtual {
        uint256 amount = 1e8;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(ptLbtcToken),
            100,
            123
        );
        quoteData.fromToken = address(lbtcToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(lbtcToken)));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_zeroAmount() public virtual {
        uint256 amount = 1e8;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(ptLbtcToken),
            100,
            123
        );
        quoteData.fromTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_success() public virtual {
        uint256 amount = 1e8;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(ptLbtcToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        deal(address(ptLbtcToken), address(manager), amount);
        uint256 amountOut = manager.investWithToken(alice, quoteData);

        assertEq(amountOut, 1e18); // deposit fee
        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(manager.reservesBalance(), amount);
    }
}

contract OrigamiLovTokenMorphoManagerTestExit_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    using OrigamiMath for uint256;
    
    function test_maxExit_fail_badAsset() public virtual {
        assertEq(manager.maxExit(alice), 0);
    }

    function test_maxExit_reserveToken() public virtual {
        vm.startPrank(origamiMultisig);
        
        // No token supply no reserves
        {
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(ptLbtcToken)), 0);
        }

        // with reserves, no liabilities. Capped at total supply (10e18)
        {
            uint256 shares = investLovToken(alice, 0.2e8 / 2);
            assertEq(shares, 0.1e18);
            assertEq(manager.reservesBalance(), 0.1e8);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(ptLbtcToken)), 0.1e18);
        }

        // Only rebalance a little. A/L is still 11. Still capped at total supply (10e18)
        {
            doRebalanceDownFor(0.0001e8, 0);
            uint256 expectedReserves = 0.1e8 + 0.0001e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.0001e8 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.0001e8 + 1);
            assertEq(manager.maxExit(address(ptLbtcToken)), 0.1e18);
        }

        // Rebalance down properly
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 0.49999992e8;
            uint256 expectedLiabilities = 0.39999993e8;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxExit(address(ptLbtcToken)), 0.043714290085714722e18);
        }

        {
            vm.startPrank(origamiMultisig);
            manager.setUserALRange(1.111111112e18, 2e18);
            manager.setRebalanceALRange(1.111111112e18, 2e18);
            doRebalanceUp(1.5e18, 0, 5);
            assertEq(manager.maxExit(address(ptLbtcToken)), 0.079365079365079364e18);
        }

        {
            assertEq(borrowLend.availableToBorrow(), 79.57547790e8);
            assertEq(borrowLend.availableToWithdraw(), 0.29999996e8);
        }
    }

    function test_exitQuote_badToken_gives0() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            100,
            alice,
            100,
            123
        );

        assertEq(quoteData.investmentTokenAmount, 100);
        assertEq(quoteData.toToken, alice);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, 0);
        assertEq(quoteData.minToTokenAmount, 0);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], 200);
    }

    function test_exitQuote_reserveToken() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            1e18,
            address(ptLbtcToken),
            100,
            123
        );

        assertEq(quoteData.investmentTokenAmount, 1e18);
        assertEq(quoteData.toToken, address(ptLbtcToken));
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, 0.98e8);
        assertEq(quoteData.minToTokenAmount, 0.9702e8);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], 200);
    }

    function test_exitToToken_fail_badToken() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(ptLbtcToken),
            100,
            123
        );

        quoteData.toToken = address(lbtcToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(lbtcToken)));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_zeroAmount() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(ptLbtcToken),
            100,
            123
        );

        quoteData.investmentTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_success() public virtual {
        uint256 investAmount = 1e8;
        uint256 shares = investLovToken(alice, investAmount);
        assertEq(shares, 1e18);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            shares,
            address(ptLbtcToken),
            100,
            200
        );

        vm.startPrank(address(lovToken));
        (uint256 amountBack, uint256 toBurn) = manager.exitToToken(alice, quoteData, bob);

        assertEq(amountBack, 0.98e8); // exit fee 
        assertEq(toBurn, shares);
        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(manager.reservesBalance(), 0.02e8);
        assertEq(ptLbtcToken.balanceOf(bob), amountBack);
    }
}

contract OrigamiLovTokenMorphoManagerTestRebalanceDown_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceDown_fail_fresh() public virtual {
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_fail_slippage() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        params.supplyAmount = 0.2e8;
        params.borrowAmount = 0.1e8;
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.borrowAmount
        }));
        deal(address(ptLbtcToken), address(swapper), params.borrowAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, params.supplyAmount, params.borrowAmount));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_success_noSupply() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;

        params.supplyAmount = 1.2e8;
        params.borrowAmount = 1e8;
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.supplyAmount
        }));
        deal(address(ptLbtcToken), address(swapper), params.supplyAmount);
        params.minNewAL = 1.18e18;
        params.minNewAL = convertAL(params.minNewAL);
        params.maxNewAL = 1.19e18;
        params.maxNewAL = convertAL(params.maxNewAL);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);

        (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 1.2e8);
        assertEq(liabilities, 1.01691482e8);
        assertEq(ratio, 1.180039838538295665e18);
    
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 1.2e8);
        assertEq(liabilities, 1.01691482e8);
        assertEq(ratio, 1.180039838538295665e18);
    }

    function test_rebalanceDown_fail_al_validation() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);

        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);

        uint256 expectedActualAl = 1.249999993750000031e18; // almost got the target exactly

        // Can't be < minNewAL
        params.minNewAL = uint128(expectedActualAl+1);
        params.minNewAL = convertAL(params.minNewAL);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, expectedActualAl, expectedActualAl+1));
        manager.rebalanceDown(params);

        // Can't be > maxNewAL
        params.minNewAL = uint128(expectedActualAl);
        params.minNewAL = convertAL(params.minNewAL);

        params.maxNewAL = uint128(expectedActualAl-1);
        params.maxNewAL = convertAL(params.maxNewAL);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, type(uint128).max, expectedActualAl, expectedActualAl-1));
        manager.rebalanceDown(params);

        // A successful rebalance, just above the real target
        doRebalanceDown(TARGET_AL + 0.0002e18, 0, slippageBps);

        // Now do another rebalance, but we get a 30% BETTER swap when going
        // PT LBTC -> LBTC
        // Meaning we have more reserves, so A/L is higher than we started out.
        {
            (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, 200);

            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: reservesAmount*1.3e8/1e8
            }));
            deal(address(ptLbtcToken), address(swapper), reservesAmount*1.3e8/1e8);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.250199993615896835e18, 1.250239805009592200e18, 1.250199993615896835e18));
            manager.rebalanceDown(params);
        }
    }

    function test_rebalanceDown_fail_al_floor() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = rebalanceALRange.floor;
        uint256 slippageBps = 0;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
            deal(address(ptLbtcToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.176499995834600014e18, 1.176500000000000000e18));
        manager.rebalanceDown(params);
    }
    
    function test_rebalanceDown_success_withEvent() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 2e8;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            1.249999993750000031e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.assetToLiabilityRatio(), 1.249999993750000031e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
    }
    
    function test_rebalanceDown_success_surplus_underThreshold() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        params.supplyCollateralSurplusThreshold = 0.005e8;
        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 2e8;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(params.supplyAmount),
            int256(params.borrowAmount),
            type(uint128).max,
            1.247999993760000031e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded - 0.004e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.assetToLiabilityRatio(), 1.247999993760000031e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0.004e8);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), 0);
    }
    
    function test_rebalanceDown_success_surplus_overThreshold() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        params.supplyCollateralSurplusThreshold = 0.003e8;
        deal(address(ptLbtcToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 2e8;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            1.249999993750000031e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.assetToLiabilityRatio(), 1.249999993750000031e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceDown_success_al_floor_force() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(uint128(targetAL + 0.01e18), rebalanceALRange.ceiling);
            
        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
            deal(address(ptLbtcToken), address(swapper), reservesAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.249999993750000031e18, 1.26e18));
        manager.rebalanceDown(params);

        uint256 expectedCollateralAdded = 2e8;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            1.249999993750000031e18
        );
        manager.forceRebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.assetToLiabilityRatio(), 1.249999993750000031e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
    }
}

contract OrigamiLovTokenMorphoManagerTestRebalanceUp_6dpReserve is OrigamiLovTokenMorphoManagerTestBase_6dpReserve {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceUp_fail_noDebt() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = IOrigamiLovTokenMorphoManager.RebalanceUpParams({
            repayAmount: 0.001e8,
            withdrawCollateralAmount: 0.001e8,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 0.001e8
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 0.001e8
        });

        vm.startPrank(origamiMultisig);
        vm.expectPartialRevert(IOrigamiLovTokenManager.ALTooHigh.selector);
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_repayTooMuch() public virtual {
        uint256 amount = 0.0001e8;
        investLovToken(alice, amount);

        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = IOrigamiLovTokenMorphoManager.RebalanceUpParams({
            repayAmount: 0.001e18,
            withdrawCollateralAmount: 0.0001e8,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 0.001e18
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 0.001e18
        });
        deal(address(lbtcToken), address(swapper), 0.001e18);

        vm.startPrank(origamiMultisig);
        vm.expectPartialRevert(IOrigamiLovTokenManager.ALTooHigh.selector);
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_noSurplus() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        {
            params.withdrawCollateralAmount = 2.0005e8;
            params.repayAmount = ptLbtcToLbtcOracle.convertAmount(
                address(ptLbtcToken),
                params.withdrawCollateralAmount,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );
            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.repayAmount
            }));
            params.minNewAL = 0;
            params.maxNewAL = type(uint128).max;
        }

        deal(address(lbtcToken), address(swapper), 500_000e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(borrowLend.debtBalance()),
            1.249999993750000031e18,
            type(uint128).max
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 0.4995e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), 0.00049168e8);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_withSurplus() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        {
            params.withdrawCollateralAmount = 1.99999e8;

            params.repayAmount = ptLbtcToLbtcOracle.convertAmount(
                address(ptLbtcToken),
                params.withdrawCollateralAmount,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );
            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.repayAmount
            }));
            params.minNewAL = 0;
            params.maxNewAL = type(uint128).max;
        }

        deal(address(lbtcToken), address(swapper), 5e8);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));

        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            1.249999993750000031e18,
            49_951.048951048951048951e18
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 0.50001e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.00001001e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.00001001e8);
        assertEq(manager.assetToLiabilityRatio(), 49_951.048951048951048951e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceUp_fail_slippage() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 10, 50);
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.repayAmount-1
        }));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, params.repayAmount, params.repayAmount-1));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_al_validation() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = 1.249999993750000031e18; // almost got the target exactly

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        uint256 expectedNewAl = 1.300000004200000142e18;

        // Can't be < minNewAL
        params.minNewAL = uint128(expectedNewAl+1);
        params.minNewAL = convertAL(params.minNewAL);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, expectedOldAl, expectedNewAl, expectedNewAl+1));
        manager.rebalanceUp(params);

        // Can't be > maxNewAL
        params.minNewAL = uint128(expectedNewAl);
        params.minNewAL = convertAL(params.minNewAL);

        params.maxNewAL = uint128(expectedNewAl-1);
        params.maxNewAL = convertAL(params.maxNewAL);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, expectedNewAl, expectedNewAl-1));
        manager.rebalanceUp(params);

        // Now do another rebalance, but withdraw and extra 30% collateral, and still
        // get the full amount of weth when swapped
        // Meaning we withdraw more collateral, so A/L is higher than we started out.
        {
            params = rebalanceUpParams(targetAL, 0, 5000);
            params.withdrawCollateralAmount = params.withdrawCollateralAmount*1.3e18/1e18;
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.249999993750000031e18, 1.239999990159999665e18, 1.249999993750000031e18));
            manager.rebalanceUp(params);
        }
    }

    function test_rebalanceUp_fail_al_ceiling() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = 1.249999993750000031e18; // almost got the target exactly

        targetAL = rebalanceALRange.ceiling+1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, 1.333400004444888948e18, rebalanceALRange.ceiling));
        manager.rebalanceUp(params);
    }
    
    function test_rebalanceUp_success_withEvent() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(manager.reservesBalance(), 2.5e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 2e8 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 2e8 + 1);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            1.249999993750000031e18,
            1.300000004200000142e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 2.16666660e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1.66666661e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.66666661e8);
        assertEq(manager.assetToLiabilityRatio(), 1.300000004200000142e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), 0);
    }
    
    function test_rebalanceUp_success_al_floor_force() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.1e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.249999993750000031e18, 1.350000004900000166e18, 1.333400000000000000e18));
        manager.rebalanceUp(params);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            1.249999993750000031e18,
            1.350000004900000166e18
        );
        manager.forceRebalanceUp(params);
    }

    function test_rebalanceUp_success_surplusUnderThreshold() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = 1.249999993750000031e18;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);
        params.repaySurplusThreshold = 0.001e8;

        uint256 expectedSurplus = 0.00065558e8;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            oldAl,
            1.299480209499566877e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 2.16666660e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1.66733328e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.66733328e8);
        assertEq(manager.assetToLiabilityRatio(), 1.299480209499566877e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
        assertEq(ptLbtcToken.balanceOf(address(borrowLend)), 0);
        assertEq(lbtcToken.balanceOf(address(borrowLend)), expectedSurplus);
    }

    function test_rebalanceUp_success_surplusOverThreshold() public virtual {
        uint256 amount = 0.5e8;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = 1.249999993750000031e18;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);
        params.repaySurplusThreshold = 0.0005e8;
        uint256 expectedSurplus = 0.00065558e8;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount + expectedSurplus),
            oldAl,
            1.300000004200000142e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 2.16666660e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1.66666661e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.66666661e8);
        assertEq(manager.assetToLiabilityRatio(), 1.300000004200000142e18);

        assertEq(ptLbtcToken.balanceOf(address(manager)), 0);
        assertEq(lbtcToken.balanceOf(address(manager)), 0);
    }
}
