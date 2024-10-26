pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMorpho } from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { ErrorsLib as MorphoErrors } from "@morpho-org/morpho-blue/src/libraries/ErrorsLib.sol";

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLovTokenMorphoManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenMorphoManager.sol";

import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenMorphoManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenMorphoManager.sol";
import { OrigamiAaveV3FlashLoanProvider } from "contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiErc4626Oracle } from "contracts/common/oracle/OrigamiErc4626Oracle.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiMorphoBorrowAndLend } from "contracts/common/borrowAndLend/OrigamiMorphoBorrowAndLend.sol";

contract OrigamiLovTokenMorphoManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    OrigamiAaveV3FlashLoanProvider internal flProvider;
    IERC20 internal daiToken;
    IERC20 internal usdeToken;
    IERC20 internal sUsdeToken;
    OrigamiLovToken internal lovToken;
    OrigamiLovTokenMorphoManager internal manager;
    TokenPrices internal tokenPrices;
    DummyLovTokenSwapper internal swapper;
    OrigamiMorphoBorrowAndLend internal borrowLend;

    IAggregatorV3Interface internal redstoneUsdeToUsdOracle;
    OrigamiStableChainlinkOracle usdeToDaiOracle;
    OrigamiErc4626Oracle sUsdeToDaiOracle;

    Range.Data internal userALRange;
    Range.Data internal rebalanceALRange;

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SUSDE_ADDRESS = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDE_ADDRESS = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_ORACLE = 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25;
    address internal constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 internal constant MORPHO_MARKET_LLTV = 0.915e18; // 91.5%
    uint96 internal constant MAX_SAFE_LLTV = 0.9e18; // 90%

    address public constant USDE_USD_ORACLE = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

    uint16 internal constant MIN_DEPOSIT_FEE_BPS = 10;
    uint16 internal constant MIN_EXIT_FEE_BPS = 50;
    uint24 internal constant FEE_LEVERAGE_FACTOR = 6e4;
    uint48 internal constant PERFORMANCE_FEE_BPS = 500;

    uint128 internal TARGET_AL = 1.25e18;                         // 80% LTV == 5x EE
    uint128 internal USER_AL_FLOOR = 1.14285714285714e18;         // 87.5% LTV == 8x EE
    uint128 internal USER_AL_CEILING = 1.42857142857143e18;       // 70% LTV == 3.33x EE
    uint128 internal REBALANCE_AL_FLOOR = 1.17647058823529e18;    // 85% LTV == 6.66x EE
    uint128 internal REBALANCE_AL_CEILING = 1.333333333334e18;    // 75% LTV == 4x EE

    uint128 internal constant USDE_USD_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 internal constant USDE_USD_MIN_THRESHOLD = 0.995e18;
    uint128 internal constant USDE_USD_MAX_THRESHOLD = 1.005e18;
    uint256 internal constant USDE_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg


    function setUp() public virtual {
        fork("mainnet", 19506752);
        vm.warp(1711311924);

        daiToken = IERC20(DAI_ADDRESS);
        sUsdeToken = IERC20(SUSDE_ADDRESS);
        usdeToken = IERC20(USDE_ADDRESS);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(
            origamiMultisig, 
            "Origami lov-sUSDe-5x", 
            "lov-sUSDe-5x", 
            PERFORMANCE_FEE_BPS, 
            feeCollector, 
            address(tokenPrices),
            type(uint256).max
        );

        borrowLend = new OrigamiMorphoBorrowAndLend(
            origamiMultisig,
            address(sUsdeToken),
            address(daiToken),
            MORPHO,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            MORPHO_MARKET_LLTV,
            MAX_SAFE_LLTV
        );
        manager = new OrigamiLovTokenMorphoManager(
            origamiMultisig, 
            address(sUsdeToken), 
            address(daiToken),
            address(usdeToken),
            address(lovToken),
            address(borrowLend)
        );
        swapper = new DummyLovTokenSwapper();

        // Oracles
        {
            redstoneUsdeToUsdOracle = IAggregatorV3Interface(USDE_USD_ORACLE);

            usdeToDaiOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "USDe/DAI",
                    address(usdeToken),
                    18,
                    address(daiToken),
                    18
                ),
                USDE_USD_HISTORIC_STABLE_PRICE,
                address(redstoneUsdeToUsdOracle),
                USDE_USD_STALENESS_THRESHOLD,
                Range.Data(USDE_USD_MIN_THRESHOLD, USDE_USD_MAX_THRESHOLD),
                false,
                true
            );
            sUsdeToDaiOracle = new OrigamiErc4626Oracle(
                IOrigamiOracle.BaseOracleParams(
                    "sUSDe/DAI",
                    address(sUsdeToken),
                    18,
                    address(daiToken),
                    18
                ),
                address(usdeToDaiOracle)
            );
        }

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(address(manager));
        borrowLend.setSwapper(address(swapper));

        userALRange = Range.Data(USER_AL_FLOOR, USER_AL_CEILING);
        rebalanceALRange = Range.Data(REBALANCE_AL_FLOOR, REBALANCE_AL_CEILING);

        manager.setOracles(address(sUsdeToDaiOracle), address(usdeToDaiOracle));
        manager.setUserALRange(userALRange.floor, userALRange.ceiling);
        manager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);
        manager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);

        lovToken.setManager(address(manager));

        vm.stopPrank();

        supplyIntoMorpho(10_000_000e18);
    }

    function convertAL(uint128 al) internal virtual view returns (uint128) {
        return al;
    }

    function supplyIntoMorpho(uint256 amount) internal {
        doMint(daiToken, origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        IMorpho morpho = borrowLend.morpho();
        SafeERC20.forceApprove(daiToken, address(morpho), amount);
        morpho.supply(borrowLend.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        deal(address(sUsdeToken), account, amount);
        vm.startPrank(account);
        sUsdeToken.approve(address(lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            amount,
            address(sUsdeToken),
            0,
            0
        );

        amountOut = lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            amount,
            address(sUsdeToken),
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

        deal(address(sUsdeToken), address(swapper), reservesAmount);

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
        params.borrowAmount = sUsdeToDaiOracle.convertAmount(
            address(sUsdeToken),
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
        params.borrowAmount = sUsdeToDaiOracle.convertAmount(
            address(sUsdeToken),
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

        deal(address(sUsdeToken), address(swapper), reservesAmount);
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

        params.repayAmount = sUsdeToDaiOracle.convertAmount(
            address(sUsdeToken),
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

contract OrigamiLovTokenMorphoManagerTestAdmin is OrigamiLovTokenMorphoManagerTestBase {
    event OraclesSet(address indexed debtTokenToReserveTokenOracle, address indexed dynamicFeePriceOracle);
    event BorrowLendSet(address indexed addr);

    function test_initialization() public virtual {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.lovToken()), address(lovToken));

        assertEq(manager.baseToken(), address(sUsdeToken));
        assertEq(manager.reserveToken(), address(sUsdeToken));
        assertEq(manager.debtToken(), address(daiToken));
        assertEq(manager.dynamicFeeOracleBaseToken(), address(usdeToken));
        assertEq(address(manager.borrowLend()), address(borrowLend));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(sUsdeToDaiOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(usdeToDaiOracle));

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
        assertEq(tokens[0], address(sUsdeToken));

        tokens = manager.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(sUsdeToken));
    }

    function test_constructor_fail() public virtual {
        // 6dp reserves
        {
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, USDT_ADDRESS));
            manager = new OrigamiLovTokenMorphoManager(
                origamiMultisig, 
                USDT_ADDRESS, // 6dp 
                address(daiToken), 
                address(usdeToken),
                address(lovToken),
                address(borrowLend)
            );
        }

        // 6dp debt - ok
        {
            manager = new OrigamiLovTokenMorphoManager(
                origamiMultisig, 
                address(sUsdeToken), 
                USDT_ADDRESS, // 6dp 
                address(usdeToken),
                address(lovToken),
                address(borrowLend)
            );
        }
    }

    function test_setOracleConfig_fail() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setOracles(address(0), address(usdeToDaiOracle));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setOracles(address(sUsdeToDaiOracle), address(0));

        OrigamiErc4626Oracle badOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDE/alice",
                address(sUsdeToken),
                18,
                alice,
                18
            ),
            address(usdeToDaiOracle)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setOracles(address(badOracle), address(usdeToDaiOracle));

        badOracle = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "alice/DAI",
                alice,
                18,
                address(daiToken),
                18
            ),
            address(usdeToDaiOracle)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setOracles(address(badOracle), address(usdeToDaiOracle));
    }

    function test_setOracles() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit OraclesSet(address(sUsdeToDaiOracle), address(usdeToDaiOracle));
        manager.setOracles(address(sUsdeToDaiOracle), address(usdeToDaiOracle));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(sUsdeToDaiOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(usdeToDaiOracle));

        OrigamiErc4626Oracle oracle1 = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "sUSDE/ETH",
                address(sUsdeToken),
                18,
                address(daiToken),
                18
            ),
            address(usdeToDaiOracle)
        );

        OrigamiErc4626Oracle oracle2 = new OrigamiErc4626Oracle(
            IOrigamiOracle.BaseOracleParams(
                "stETH/ETH",
                address(usdeToken),
                18,
                address(daiToken),
                18
            ),
            address(usdeToDaiOracle)
        );

        vm.expectEmit(address(manager));
        emit OraclesSet(address(oracle1), address(oracle2));
        manager.setOracles(address(oracle1), address(oracle2));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(oracle1));
        assertEq(address(manager.dynamicFeePriceOracle()), address(oracle2));
    }

    function test_setBorrowLend_fail() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setBorrowLend(address(0));
    }

    function test_setBorrowLend_success() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit BorrowLendSet(alice);
        manager.setBorrowLend(alice);
        assertEq(address(manager.borrowLend()), alice);
    }

    function test_setUserAlRange_failValidate() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1.111111111111111110e18, 2e18));
        manager.setUserALRange(1.111111111111111110e18, 2e18);

        assertEq(uint256(1e36)/0.9e18, 1.111111111111111111e18);

        manager.setUserALRange(1.111111111111111111e18, 2e18);
        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.111111111111111111e18);
        assertEq(ceiling, 2e18);
    }

    function test_setRebalanceAlRange_failValidate() public virtual {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1.10e18, 2e18));
        manager.setRebalanceALRange(1.10e18, 2e18);

        manager.setRebalanceALRange(1.12e18, 2e18);
        (uint128 floor, uint128 ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.12e18);
        assertEq(ceiling, 2e18);
    }

    function test_recoverToken_success() public virtual {
        check_recoverToken(address(manager));
    }
}

contract OrigamiLovTokenMorphoManagerTestAccess is OrigamiLovTokenMorphoManagerTestBase {
    function test_access_setOracles() public virtual {
        expectElevatedAccess();
        manager.setOracles(alice, alice);
    }

    function test_access_setBorrowLend() public virtual {
        expectElevatedAccess();
        manager.setBorrowLend(alice);
    }

    function test_access_rebalanceUp() public virtual {
        expectElevatedAccess();
        manager.rebalanceUp(IOrigamiLovTokenMorphoManager.RebalanceUpParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_forceRebalanceUp() public virtual {
        expectElevatedAccess();
        manager.forceRebalanceUp(IOrigamiLovTokenMorphoManager.RebalanceUpParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_rebalanceDown() public virtual {
        expectElevatedAccess();
        manager.rebalanceDown(IOrigamiLovTokenMorphoManager.RebalanceDownParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_forceRebalanceDown() public virtual {
        expectElevatedAccess();
        manager.forceRebalanceDown(IOrigamiLovTokenMorphoManager.RebalanceDownParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_recoverToken() public virtual {
        expectElevatedAccess();
        manager.recoverToken(address(sUsdeToken), alice, 123);
    }
}

contract OrigamiLovTokenMorphoManagerTestViews is OrigamiLovTokenMorphoManagerTestBase {
    function test_reservesBalance() public virtual {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        uint256 expectedReserves = amount;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        doRebalanceDown(TARGET_AL, 0, 5);
        expectedReserves = 250e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.249999999999999999e18);

        doRebalanceUp(rebalanceALRange.ceiling, 0, 5);
        expectedReserves = 199.999999999699999994e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), rebalanceALRange.ceiling);

        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        expectedReserves = 195.083083082783083073e18;
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.300553887221154995e18);
        
        assertEq(sUsdeToken.balanceOf(bob), 4.916916916916916921e18);
    }

    function test_liabilities_success() public virtual {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        doRebalanceDown(TARGET_AL, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200e18 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200.584395999999999935e18);

        doRebalanceUp(rebalanceALRange.ceiling, 0, 5);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 149.999999999699999947e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 150.438296999699123303e18);

        // Exits don't affect liabilities
        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 149.999999999699999947e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 150.438296999699123303e18);
    }

    function test_liabilities_zeroDebt() public virtual {
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_liabilities_withDebt_isPricingToken() public virtual {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200e18 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200.584395999999999935e18);
    }

    function test_liabilities_withDebt_notPricingToken() public virtual {
        // Setup the oracle so it's the inverse (DAI/sUSDe)
        vm.startPrank(origamiMultisig);

        {
            // Hack to get the reciprocal DAI/sUSDe
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
                    address(daiToken),
                    18,
                    address(daiToken),
                    18
                ),
                1e18, 
                address(clOne), 
                365 days, 
                Range.Data(1e18, 1e18),
                false,
                true
            );

            OrigamiCrossRateOracle daiToSUsde = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "DAI/sUSDe",
                    address(daiToken),
                    18,
                    address(sUsdeToken),
                    18
                ),
                address(oOne), 
                address(sUsdeToDaiOracle),
                address(0)
            );

            manager.setOracles(address(daiToSUsde), address(usdeToDaiOracle));
        }

        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200.000000000000000013e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200.584395999999999960e18);
    }

    function test_getDynamicFeesBps() public virtual {
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 10);
        assertEq(exitFee, 176);
    }
}

contract OrigamiLovTokenMorphoManagerTestInvest is OrigamiLovTokenMorphoManagerTestBase {
    using OrigamiMath for uint256;
    
    function test_maxInvest_fail_badAsset() public virtual {
        assertEq(manager.maxInvest(alice), 0);
    }

    function test_maxInvest_reserveToken() public virtual {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedAvailable);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 100_000e18);
            assertEq(manager.reservesBalance(), 100_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedAvailable);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 100_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 71_428.571428571999999997e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 499_999.999999999999999992e18;
            uint256 expectedLiabilities = 399_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 401_168.791999999999866109e18);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e6;
            deal(address(sUsdeToken), alice, investAmount);
            vm.startPrank(alice);
            sUsdeToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(sUsdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.25e18, 1.428571428571430002e18, 1.428571428571430000e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
            exitLovToken(alice, amountOut, alice);
        }
    }

    function test_maxInvest_reserveToken_withMaxTotalSupply() public virtual {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);
        uint256 maxTotalSupply = 200_000e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        // No token supply no reserves
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            // share price = 1, +fees
            assertEq(manager.maxInvest(address(sUsdeToken)), 210_526.315789473684210526e18);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 100_000e18);
            assertEq(manager.reservesBalance(), 100_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            // share price > 1, +fees
            assertEq(manager.maxInvest(address(sUsdeToken)), 116_343.490304709141274237e18);
        }

        // Only rebalance a little.
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 100_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 71_428.571428571999999997e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 499_999.999999999999999992e18;
            uint256 expectedLiabilities = 399_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 401_168.791999999999866109e18);
            assertEq(manager.maxInvest(address(sUsdeToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 1e6;
            deal(address(sUsdeToken), alice, investAmount);
            vm.startPrank(alice);
            sUsdeToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(sUsdeToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.25e18, 1.428571428571430002e18, 1.428571428571430000e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(sUsdeToken)), 0);
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
        assertEq(investFeeBps[0], 10);
    }

    function test_investQuote_reserveToken() public virtual {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            1e18,
            address(sUsdeToken),
            100,
            123
        );

        assertEq(quoteData.fromToken, address(sUsdeToken));
        assertEq(quoteData.fromTokenAmount, 1e18);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 0.999e18);
        assertEq(quoteData.minInvestmentAmount, 0.98901e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investWithToken_fail_badToken() public virtual {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(sUsdeToken),
            100,
            123
        );
        quoteData.fromToken = address(daiToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(daiToken)));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_zeroAmount() public virtual {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(sUsdeToken),
            100,
            123
        );
        quoteData.fromTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_success() public virtual {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(sUsdeToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        deal(address(sUsdeToken), address(manager), amount);
        uint256 amountOut = manager.investWithToken(alice, quoteData);

        assertEq(amountOut, 0.999e18); // deposit fee
        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(manager.reservesBalance(), amount);
    }
}

contract OrigamiLovTokenMorphoManagerTestExit is OrigamiLovTokenMorphoManagerTestBase {
    using OrigamiMath for uint256;
    
    function test_maxExit_fail_badAsset() public virtual {
        assertEq(manager.maxExit(alice), 0);
    }

    function test_maxExit_reserveToken() public virtual {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(0, 500, 0);
        
        // No token supply no reserves
        {
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(sUsdeToken)), 0);
        }

        // with reserves, no liabilities. Capped at total supply (10e18)
        {
            uint256 totalSupply = 20_000e18;
            uint256 shares = investLovToken(alice, totalSupply / 2);
            assertEq(shares, 10_000e18);
            assertEq(manager.reservesBalance(), 10_000e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(sUsdeToken)), 10_000e18);
        }

        // Only rebalance a little. A/L is still 11. Still capped at total supply (10e18)
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10_000e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18 + 1);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.00292198e18 + 1);
            assertEq(manager.maxExit(address(sUsdeToken)), 10_000e18);
        }

        // Rebalance down properly
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 49_999.999999999999999992e18;
            uint256 expectedLiabilities = 39_999.999999999999999993e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 40_116.879199999999986604e18);
            assertEq(manager.maxExit(address(sUsdeToken)), 4_511.278195488842105262e18);
        }

        {
            vm.startPrank(origamiMultisig);
            manager.setUserALRange(1.111111112e18, 2e18);
            manager.setRebalanceALRange(1.111111112e18, 2e18);
            doRebalanceUp(1.5e18, 0, 5);
            assertEq(manager.maxExit(address(sUsdeToken)), 8_187.134484210526322552e18);
        }

        // An external withdraw of supply does not impact our collateral and amount
        // which can be exited
        {
            assertEq(borrowLend.availableToBorrow(), 9_979_248.978174019999743496e18);
            assertEq(borrowLend.availableToWithdraw(), 29_999.999999999999999996e18);

            vm.startPrank(origamiMultisig);
            IMorpho morpho = borrowLend.morpho();
            morpho.withdraw(borrowLend.getMarketParams(), 9_979_000e18, 0, origamiMultisig, origamiMultisig);
            vm.stopPrank();

            assertEq(borrowLend.availableToBorrow(), 248.978174019999743496e18);
            assertEq(borrowLend.availableToWithdraw(), 29_999.999999999999999996e18);
        }

        assertEq(manager.maxExit(address(sUsdeToken)), 8_187.134484210526322552e18);
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
        assertEq(exitFeeBps[0], 176);
    }

    function test_exitQuote_reserveToken() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            1e18,
            address(sUsdeToken),
            100,
            123
        );

        assertEq(quoteData.investmentTokenAmount, 1e18);
        assertEq(quoteData.toToken, address(sUsdeToken));
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, 0.9824e18);
        assertEq(quoteData.minToTokenAmount, 0.972576e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], 176);
    }

    function test_exitToToken_fail_badToken() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(sUsdeToken),
            100,
            123
        );

        quoteData.toToken = address(daiToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(daiToken)));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_zeroAmount() public virtual {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(sUsdeToken),
            100,
            123
        );

        quoteData.investmentTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_success() public virtual {
        uint256 investAmount = 1e18;
        uint256 shares = investLovToken(alice, investAmount);
        assertEq(shares, 0.999e18);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            shares,
            address(sUsdeToken),
            100,
            123
        );

        vm.startPrank(address(lovToken));
        (uint256 amountBack, uint256 toBurn) = manager.exitToToken(alice, quoteData, bob);

        assertEq(amountBack, 0.9824e18); // exit fee 
        assertEq(toBurn, shares);
        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(manager.reservesBalance(), 0.0176e18);
        assertEq(sUsdeToken.balanceOf(bob), amountBack);
    }
}

contract OrigamiLovTokenMorphoManagerTestRebalanceDown is OrigamiLovTokenMorphoManagerTestBase {
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
        deal(address(sUsdeToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(MorphoErrors.ZERO_ASSETS));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_fail_slippage() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;
        params.supplyAmount = 20e18;
        params.borrowAmount = 10e18;
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.borrowAmount
        }));
        deal(address(sUsdeToken), address(swapper), params.borrowAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, params.supplyAmount, params.borrowAmount));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_success_noSupply() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params;

        params.supplyAmount = 11.5e18;
        params.borrowAmount = 10e18;
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.supplyAmount
        }));
        deal(address(sUsdeToken), address(swapper), params.supplyAmount);
        params.minNewAL = 1.19e18;
        params.minNewAL = convertAL(params.minNewAL);
        params.maxNewAL = 1.20e18;
        params.maxNewAL = convertAL(params.maxNewAL);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);

        (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 11.5e18);
        assertEq(liabilities, 9.638079127764797341e18);
        assertEq(ratio, 1.193183812620036834e18);
    
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 11.5e18);
        assertEq(liabilities, 9.666241402214543520e18);
        assertEq(ratio, 1.189707511066849720e18);
    }

    function test_rebalanceDown_fail_al_validation() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);

        deal(address(sUsdeToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);

        uint256 expectedActualAl = targetAL - 1; // almost got the target exactly

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
        // sUSDe->DAI
        // Meaning we have more reserves, so A/L is higher than we started out.
        {
            (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, 200);

            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: reservesAmount*1.3e18/1e18
            }));
            deal(address(sUsdeToken), address(swapper), reservesAmount*1.3e18/1e18);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.250199999999999999e18, 1.250239808153477218e18, 1.250199999999999999e18));
            manager.rebalanceDown(params);
        }
    }

    function test_rebalanceDown_fail_al_floor() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = rebalanceALRange.floor;
        uint256 slippageBps = 0;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
            deal(address(sUsdeToken), address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.176470588235289999e18, 1.176470588235290000e18));
        manager.rebalanceDown(params);
    }
    
    function test_rebalanceDown_success_withEvent() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(sUsdeToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 200_000e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            targetAL-1
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
    }
    
    function test_rebalanceDown_success_surplus_underThreshold() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        params.supplyCollateralSurplusThreshold = 500e18;
        deal(address(sUsdeToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 200_000e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(params.supplyAmount),
            int256(params.borrowAmount),
            type(uint128).max,
            1.247999999999999999e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded - 400e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);
        assertEq(manager.assetToLiabilityRatio(), 1.247999999999999999e18);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 400e18);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
    }
    
    function test_rebalanceDown_success_surplus_overThreshold() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        params.supplyCollateralSurplusThreshold = 300e18;
        deal(address(sUsdeToken), address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 200_000e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            1.249999999999999999e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);
        assertEq(manager.assetToLiabilityRatio(), 1.249999999999999999e18);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceDown_success_al_floor_force() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(uint128(targetAL + 0.01e18), rebalanceALRange.ceiling);
            
        (IOrigamiLovTokenMorphoManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
            deal(address(sUsdeToken), address(swapper), reservesAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.249999999999999999e18, 1.26e18));
        manager.rebalanceDown(params);

        uint256 expectedCollateralAdded = 200_000e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.borrowAmount),
            type(uint128).max,
            targetAL-1
        );
        manager.forceRebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
    }
}

contract OrigamiLovTokenMorphoManagerTestRebalanceUp is OrigamiLovTokenMorphoManagerTestBase {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceUp_fail_noDebt() public virtual {
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = IOrigamiLovTokenMorphoManager.RebalanceUpParams({
            repayAmount: 10e18,
            withdrawCollateralAmount: 10e18,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e18
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(daiToken), 10e18));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_repayTooMuch() public virtual {
        uint256 amount = 1e18;
        investLovToken(alice, amount);

        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = IOrigamiLovTokenMorphoManager.RebalanceUpParams({
            repayAmount: 10e18,
            withdrawCollateralAmount: 1e18,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e18
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });
        deal(address(daiToken), address(swapper), 10e18);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(daiToken), 10e18));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_noSurplus() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        {
            params.withdrawCollateralAmount = 200_050e18;
            params.repayAmount = sUsdeToDaiOracle.convertAmount(
                address(sUsdeToken),
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

        deal(address(daiToken), address(swapper), 500_000e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(borrowLend.debtBalance()),
            targetAL-1,
            type(uint128).max
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 49_950e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 51.877557070436584149e18);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_withSurplus() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params;
        {
            params.withdrawCollateralAmount = 199_999e18;

            params.repayAmount = sUsdeToDaiOracle.convertAmount(
                address(sUsdeToken),
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

        deal(address(daiToken), address(swapper), 500_000e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));

        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            targetAL-1,
            50_001.000000009638142759e18
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 50_001e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.999999999999807241e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1.002921979999806677e18);
        assertEq(manager.assetToLiabilityRatio(), 50_001.000000009638142759e18);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceUp_fail_slippage() public virtual {
        uint256 amount = 50_000e18;
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
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        uint256 expectedNewAl = targetAL;

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
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.249999999999999999e18, 1.24e18, 1.249999999999999999e18));
            manager.rebalanceUp(params);
        }
    }

    function test_rebalanceUp_fail_al_ceiling() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = rebalanceALRange.ceiling+1;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, targetAL, rebalanceALRange.ceiling));
        manager.rebalanceUp(params);
    }
    
    function test_rebalanceUp_success_withEvent() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(manager.reservesBalance(), 250_000e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 200_000e18 + 1);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 200_584.395999999999933060e18);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            TARGET_AL-1,
            targetAL
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 216_666.666666666666666660e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 166_666.666666666666634534e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 167_153.663333333333245322e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), 0);
    }
    
    function test_rebalanceUp_success_al_floor_force() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.1e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, TARGET_AL-1, targetAL, 1.333333333334000000e18));
        manager.rebalanceUp(params);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            TARGET_AL-1,
            targetAL
        );
        manager.forceRebalanceUp(params);
    }

    function test_rebalanceUp_success_surplusUnderThreshold() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);
        params.repaySurplusThreshold = 100e18;

        uint256 expectedSurplus = 69.170076093915178867e18;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount),
            oldAl,
            1.299480207916833266e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 216_666.666666666666666660e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 166_733.333333333333301265e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 167_220.524798666666578698e18);
        assertEq(manager.assetToLiabilityRatio(), 1.299480207916833266e18);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
        assertEq(sUsdeToken.balanceOf(address(borrowLend)), 0);
        assertEq(daiToken.balanceOf(address(borrowLend)), expectedSurplus);
    }

    function test_rebalanceUp_success_surplusOverThreshold() public virtual {
        uint256 amount = 50_000e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenMorphoManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);
        params.repaySurplusThreshold = 50e18;
        uint256 expectedSurplus = 69.170076093915178867e18;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.withdrawCollateralAmount),
            -int256(params.repayAmount + expectedSurplus),
            oldAl,
            targetAL
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 216_666.666666666666666660e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 166_666.666666666666634534e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 167_153.663333333333245322e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL);

        assertEq(sUsdeToken.balanceOf(address(manager)), 0);
        assertEq(daiToken.balanceOf(address(manager)), 0);
    }
}
