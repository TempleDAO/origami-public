pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Errors as AaveErrors } from "@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { ReserveConfiguration as AaveReserveConfiguration } from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

import { IAggregatorV3Interface } from "contracts/interfaces/external/chainlink/IAggregatorV3Interface.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiLovTokenManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenManager.sol";
import { IOrigamiLovTokenFlashAndBorrowManager } from "contracts/interfaces/investments/lovToken/managers/IOrigamiLovTokenFlashAndBorrowManager.sol";

import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { OrigamiLovTokenFlashAndBorrowManager } from "contracts/investments/lovToken/managers/OrigamiLovTokenFlashAndBorrowManager.sol";
import { OrigamiAaveV3FlashLoanProvider } from "contracts/common/flashLoan/OrigamiAaveV3FlashLoanProvider.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { OrigamiVolatileChainlinkOracle } from "contracts/common/oracle/OrigamiVolatileChainlinkOracle.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    OrigamiAaveV3FlashLoanProvider internal flProvider;
    IERC20 internal wethToken;
    IERC20 internal wbtcToken;
    OrigamiLovToken internal lovToken;
    OrigamiLovTokenFlashAndBorrowManager internal manager;
    TokenPrices internal tokenPrices;
    DummyLovTokenSwapper internal swapper;
    OrigamiAaveV3BorrowAndLend internal borrowLend;

    IAggregatorV3Interface internal clEthToWbtcOracle;
    OrigamiVolatileChainlinkOracle wEthToWbtcOracle;

    Range.Data internal userALRange;
    Range.Data internal rebalanceALRange;

    uint256 internal repaySurplusThreshold = 0;

    address internal constant SPARK_POOL_ADDRESS_PROVIDER = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address internal constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant CL_ETH_BTC_ORACLE = 0xAc559F25B1619171CbC396a50854A3240b6A4e99;
    address internal constant SPARK_A_WETH_ADDRESS = 0x59cD1C87501baa753d0B5B5Ab5D8416A45cD71DB;
    address internal constant SPARK_D_WBTC_ADDRESS = 0xf6fEe3A8aC8040C3d6d81d9A4a168516Ec9B51D2;

    uint16 internal constant MIN_DEPOSIT_FEE_BPS = 10;
    uint16 internal constant MIN_EXIT_FEE_BPS = 50;
    uint24 internal constant FEE_LEVERAGE_FACTOR = 15e4;
    uint48 internal constant PERFORMANCE_FEE_BPS = 500;

    uint256 internal constant TARGET_AL = 1.75e18; // 57% LTV

    uint128 internal constant ETH_BTC_STALENESS_THRESHOLD = 1 hours + 5 minutes; // It should update every 3600 seconds. So set to 1hr 5mins
    uint8 internal constant SPARK_EMODE_NONE = 0;

    function setUp() public {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        wbtcToken = IERC20(WBTC_ADDRESS);
        wethToken = IERC20(WETH_ADDRESS);

        flProvider = new OrigamiAaveV3FlashLoanProvider(SPARK_POOL_ADDRESS_PROVIDER);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(
            origamiMultisig, 
            "Origami lov-wETH-wBTC", 
            "lov-wETH-wBTC", 
            PERFORMANCE_FEE_BPS, 
            feeCollector, 
            address(tokenPrices),
            type(uint256).max
        );

        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig,
            address(wethToken),
            address(wbtcToken),
            SPARK_POOL,
            SPARK_EMODE_NONE
        );
        manager = new OrigamiLovTokenFlashAndBorrowManager(
            origamiMultisig, 
            address(wethToken), 
            address(wbtcToken),
            address(wethToken), 
            address(lovToken),
            address(flProvider),
            address(borrowLend)
        );
        swapper = new DummyLovTokenSwapper();

        // Oracles
        {
            clEthToWbtcOracle = IAggregatorV3Interface(CL_ETH_BTC_ORACLE);

            wEthToWbtcOracle = new OrigamiVolatileChainlinkOracle(
                IOrigamiOracle.BaseOracleParams(
                    "wETH/wBTC",
                    address(wethToken),
                    18,
                    address(wbtcToken),
                    8
                ),
                address(clEthToWbtcOracle),
                ETH_BTC_STALENESS_THRESHOLD,
                true,
                true
            );
        }

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(address(manager));
        lovToken.setManager(address(manager));
        manager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);
        manager.setSwapper(address(swapper));
        manager.setOracles(address(wEthToWbtcOracle), address(wEthToWbtcOracle));

        userALRange = Range.Data(1.5e18, 1.9e18);
        rebalanceALRange = Range.Data(1.47e18, 2e18);

        manager.setUserALRange(userALRange.floor, userALRange.ceiling);
        manager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);

        vm.stopPrank();
    }

    function investLovToken(address account, uint256 amount) internal returns (uint256 amountOut) {
        deal(address(wethToken), account, amount, false);
        vm.startPrank(account);
        wethToken.approve(address(lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            amount,
            address(wethToken),
            0,
            0
        );

        amountOut = lovToken.investWithToken(quoteData);
    }

    function exitLovToken(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            amount,
            address(wethToken),
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
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params;
        (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, alSlippageBps);

        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);
    }

    function rebalanceDownParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params,
        uint256 reservesAmount
    ) {
        reservesAmount = LovTokenHelpers.solveRebalanceDownAmount(manager, targetAL);
        params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
            address(wethToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
        params.minExpectedReserveToken = OrigamiMath.subtractBps(reservesAmount, swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    function doRebalanceDownFor(
        uint256 reservesAmount, 
        uint256 slippageBps
    ) internal {
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params;
        params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
            address(wethToken),
            reservesAmount,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));

        params.minNewAL = 0;
        params.maxNewAL = type(uint128).max;
        params.minExpectedReserveToken = OrigamiMath.subtractBps(reservesAmount, slippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        deal(address(wethToken), address(swapper), reservesAmount, false);
        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(params);
    }

    // Decrease liabilities to raise A/L
    function doRebalanceUp(
        uint256 targetAL, 
        uint256 slippageBps, 
        uint256 alSlippageBps
    ) internal virtual {
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, slippageBps, alSlippageBps);
        vm.startPrank(origamiMultisig);
        manager.rebalanceUp(params);
    }
    
    function rebalanceUpParams(
        uint256 targetAL,
        uint256 swapSlippageBps,
        uint256 alSlippageBps
    ) internal virtual view returns (
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params
    ) {
        // ideal reserves (wstETH) amount to remove
        params.collateralToWithdraw = LovTokenHelpers.solveRebalanceUpAmount(manager, targetAL);

        params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
            address(wethToken),
            params.collateralToWithdraw,
            IOrigamiOracle.PriceType.SPOT_PRICE,
            OrigamiMath.Rounding.ROUND_UP
        );

        // The amount we'll get for swapping params.collateralToWithdraw
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.flashLoanAmount
        }));

        // The `params.flashLoanAmount` calculated so far is the total amount we want to have to repay for
        // the flashloan. If there's a fee (currently disabled on Spark) then discount that first.
        uint128 flFee = flProvider.POOL().FLASHLOAN_PREMIUM_TOTAL();
        params.flashLoanAmount = params.flashLoanAmount.mulDiv(
            OrigamiMath.BASIS_POINTS_DIVISOR, 
            OrigamiMath.BASIS_POINTS_DIVISOR + flFee,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        // Apply slippage to the amount what's actually flashloaned is the lowest amount which
        // we would get when converting the collateral [wstETH] to the flashloan asset [wbtc].
        // We need to be sure it can be paid off. Any remaining wbtc is repaid on the wbtc debt in Spark
        params.flashLoanAmount = params.flashLoanAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = repaySurplusThreshold;

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }

}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestAdmin is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    event OraclesSet(address indexed debtTokenToReserveTokenOracle, address indexed dynamicFeePriceOracle);
    event SwapperSet(address indexed swapper);
    event FlashLoanProviderSet(address indexed provider);
    event BorrowLendSet(address indexed addr);

    function test_initialization() public {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.lovToken()), address(lovToken));

        assertEq(manager.baseToken(), address(wethToken));
        assertEq(manager.reserveToken(), address(wethToken));
        assertEq(manager.debtToken(), address(wbtcToken));
        assertEq(manager.dynamicFeeOracleBaseToken(), address(wethToken));
        assertEq(address(borrowLend.aavePool()), SPARK_POOL);
        assertEq(address(borrowLend.aaveAToken()), SPARK_A_WETH_ADDRESS);
        assertEq(address(borrowLend.aaveDebtToken()), SPARK_D_WBTC_ADDRESS);
        assertEq(address(manager.flashLoanProvider()), address(flProvider));
        assertEq(address(manager.swapper()), address(swapper));      
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(wEthToWbtcOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(wEthToWbtcOracle));

        (uint64 minDepositFee, uint64 minExitFee, uint64 feeLeverageFactor) = manager.getFeeConfig();
        assertEq(minDepositFee, MIN_DEPOSIT_FEE_BPS);
        assertEq(minExitFee, MIN_EXIT_FEE_BPS);
        assertEq(feeLeverageFactor, FEE_LEVERAGE_FACTOR);

        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.5e18);
        assertEq(ceiling, 1.9e18);

        (floor, ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.47e18);
        assertEq(ceiling, 2e18);

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
        assertEq(tokens[0], address(wethToken));

        tokens = manager.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(wethToken));
    }

    function test_setSwapper_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setSwapper(address(0));
    }

    function test_setSwapper_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit SwapperSet(alice);
        manager.setSwapper(alice);
        assertEq(address(manager.swapper()), alice);
        assertEq(wethToken.allowance(address(manager), alice), type(uint256).max);
        assertEq(wbtcToken.allowance(address(manager), alice), type(uint256).max);

        vm.expectEmit(address(manager));
        emit SwapperSet(bob);
        manager.setSwapper(bob);
        assertEq(address(manager.swapper()), bob);
        assertEq(wethToken.allowance(address(manager), alice), 0);
        assertEq(wethToken.allowance(address(manager), bob), type(uint256).max);
        assertEq(wbtcToken.allowance(address(manager), alice), 0);
        assertEq(wbtcToken.allowance(address(manager), bob), type(uint256).max);
    }

    function test_setFlashLoanProvider_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setFlashLoanProvider(address(0));
    }

    function test_setFlashLoanProvider_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FlashLoanProviderSet(alice);
        manager.setFlashLoanProvider(alice);
        assertEq(address(manager.flashLoanProvider()), alice);
    }

    function test_setBorrowLend_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setBorrowLend(address(0));
    }

    function test_setBorrowLend_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit BorrowLendSet(alice);
        manager.setBorrowLend(alice);
        assertEq(address(manager.borrowLend()), alice);
    }

    function test_setUserAlRange_failValidate() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1.10e18, 2e18));
        manager.setUserALRange(1.10e18, 2e18);

        manager.setUserALRange(1.55e18, 1.65e18);
        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.55e18);
        assertEq(ceiling, 1.65e18);

    }

    function test_setRebalanceAlRange_failValidate() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1.10e18, 2e18));
        manager.setRebalanceALRange(1.10e18, 2e18);

        manager.setRebalanceALRange(1.49e18, 1.59e18);
        (uint128 floor, uint128 ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.49e18);
        assertEq(ceiling, 1.59e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }

    function test_flashLoanCallback_fail_badToken() public {
        vm.startPrank(address(flProvider));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wethToken)));
        manager.flashLoanCallback(wethToken, 123, 123, bytes(""));
    }

    function test_flashLoanCallback_fail_badParams() public {
        vm.startPrank(address(flProvider));

        // This could still abi decode some other data, but it can only be called from a trusted
        // address
        bytes memory params = abi.encode(
            OrigamiLovTokenFlashAndBorrowManager.RebalanceCallbackType.REBALANCE_UP,
            false,
            abi.encode(123)
        );

        vm.expectRevert();
        manager.flashLoanCallback(wbtcToken, 123, 123, params);
    }

    function test_rebalanceDownFlashLoanCallback_fail_badAmount() public {
        vm.startPrank(address(flProvider));

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory rbdParams;
        rbdParams.flashLoanAmount = 666;
        bytes memory params = abi.encode(
            OrigamiLovTokenFlashAndBorrowManager.RebalanceCallbackType.REBALANCE_DOWN,
            false,
            abi.encode(rbdParams)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.flashLoanCallback(wbtcToken, 123, 123, params);
    }

    function test_rebalanceUpFlashLoanCallback_fail_badAmount() public {
        vm.startPrank(address(flProvider));

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory rbuParams;
        rbuParams.flashLoanAmount = 666;
        bytes memory params = abi.encode(
            OrigamiLovTokenFlashAndBorrowManager.RebalanceCallbackType.REBALANCE_UP,
            false,
            abi.encode(rbuParams)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.flashLoanCallback(wbtcToken, 123, 123, params);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestAccess is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    function test_access_setSwapper() public {
        expectElevatedAccess();
        manager.setSwapper(alice);
    }

    function test_access_setBorrowLend() public {
        expectElevatedAccess();
        manager.setBorrowLend(alice);
    }

    function test_access_setOracle() public {
        expectElevatedAccess();
        manager.setOracles(alice, alice);
    }

    function test_access_setFlashLoanProvider() public {
        expectElevatedAccess();
        manager.setFlashLoanProvider(alice);
    }

    function test_access_rebalanceUp() public {
        expectElevatedAccess();
        manager.rebalanceUp(IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_forceRebalanceUp() public {
        expectElevatedAccess();
        manager.forceRebalanceUp(IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams(0, 0, bytes(""), 0, 0, 0));
    }

    function test_access_rebalanceDown() public {
        expectElevatedAccess();
        manager.rebalanceDown(IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams(0, 0, bytes(""), 0, 0));
    }

    function test_access_forceRebalanceDown() public {
        expectElevatedAccess();
        manager.forceRebalanceDown(IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams(0, 0, bytes(""), 0, 0));
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        manager.recoverToken(address(wethToken), alice, 123);
    }

    function test_access_flashLoanCallback() public {
        expectElevatedAccess();
        manager.flashLoanCallback(wethToken, 123, 123, bytes(""));
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestViews is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    function test_reservesBalance() public {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        uint256 expectedReserves = amount;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        doRebalanceDown(TARGET_AL, 0, 5);
        expectedReserves = 116.666666666666666667e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), TARGET_AL-1); // almost nailed it, slight rounding diff

        doRebalanceUp(rebalanceALRange.ceiling - 0.001e18, 0, 5);
        expectedReserves = 100.050050050050050049e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.999000004876799231e18);

        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        expectedReserves = 95.070070057908652785e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.899500004391071980e18);
        
        assertEq(wethToken.balanceOf(bob), 4.979979992141397264e18);
    }

    function test_liabilities_success() public {
        uint256 amount = 50e18;

        investLovToken(alice, amount);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        doRebalanceDown(TARGET_AL, 0, 5);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.63991200e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 66.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666667e18);

        doRebalanceUp(rebalanceALRange.ceiling - 0.001e18, 0, 5);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 2.73266666e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 50.050049927946976008e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.050049927946976008e18);

        // Exits don't affect liabilities
        uint256 exitAmount = 5e18;
        exitLovToken(alice, exitAmount, bob);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 2.73266666e8);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 50.050049927946976008e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 50.050049927946976008e18);
    }

    function test_liabilities_zeroDebt() public {
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_liabilities_withDebt_isPricingToken() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 66.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666667e18);
    }

    function test_liabilities_withDebt_notPricingToken() public {
        // Setup the oracle so it's the inverse (ETH/wstETH)
        vm.startPrank(origamiMultisig);

        {
            // Hack to get the reciprocal ETH/wstETH
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
            OrigamiVolatileChainlinkOracle oOne = new OrigamiVolatileChainlinkOracle(
                IOrigamiOracle.BaseOracleParams(
                    "ONE/ONE", 
                    address(wbtcToken),
                    18,
                    address(wbtcToken),
                    18
                ),
                address(clOne), 
                365 days, 
                false,
                true
            );

            OrigamiCrossRateOracle btcToEth = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "wBTC/wETH",
                    address(wbtcToken),
                    8,
                    address(wethToken),
                    18
                ),
                address(oOne), 
                address(wEthToWbtcOracle),
                address(0)
            );

            manager.setOracles(address(btcToEth), address(btcToEth));
        }

        uint256 amount = 50e18;
        investLovToken(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 66.666666666666666668e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666668e18);
    }

    function test_getDynamicFeesBps() public {
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 10);
        assertEq(exitFee, 50);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestInvest is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    using OrigamiMath for uint256;
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    function test_maxInvest_fail_badAsset() public {
        assertEq(manager.maxInvest(alice), 0);
    }

    function test_availableSupply() public {
        (uint256 supplyCap, uint256 expectedAvailable) = borrowLend.availableToSupply();
        assertEq(supplyCap, type(uint256).max);
        assertEq(expectedAvailable, type(uint256).max);

        IAavePool pool = borrowLend.aavePool();
        AaveDataTypes.ReserveData memory _reserveData = pool.getReserveData(address(wethToken));
        assertEq(_reserveData.configuration.getSupplyCap(), 0);
        assertEq(_reserveData.configuration.getBorrowCap(), 1_400_000);

        expectedAvailable = borrowLend.availableToBorrow();
        assertEq(expectedAvailable, 2_000e8);
        _reserveData = pool.getReserveData(address(wbtcToken));
        assertEq(_reserveData.configuration.getSupplyCap(), 5_000);
        assertEq(_reserveData.configuration.getBorrowCap(), 2_000);
    }

    function test_maxInvest_reserveToken() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        // No token supply no reserves
        // Capped to the remaining space in the spark supply.
        // max 800k, already supplied 407k = 393k remaining space
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxInvest(address(wethToken)), expectedAvailable);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            // Almost exactly 10. Aave took a tiny fee.
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.maxInvest(address(wethToken)), expectedAvailable);
        }

        // Only rebalance a little. A/L is still 11
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18 - 1;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
            assertEq(manager.maxInvest(address(wethToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 1.999999652006238981e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 23.333333333333333332e18;
            uint256 expectedLiabilities = 13.333333150178722270e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxInvest(address(wethToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 100;
            deal(address(wethToken), alice, investAmount, false);
            vm.startPrank(alice);
            wethToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(wethToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.750000024039043032e18, 1.900000000000000007e18, 1.9e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(wethToken)), 1);
            exitLovToken(alice, amountOut, alice);
        }

        // Do an external huge deposit into spark to max out the available supply, except 1 eth
        {
            uint256 extAmount = 10_000e18;
            deal(address(wethToken), bob, extAmount);
            vm.startPrank(bob);
            wethToken.approve(address(borrowLend.aavePool()), extAmount);
            borrowLend.aavePool().supply(address(wethToken), extAmount, bob, 0);
        }

        assertEq(manager.maxInvest(address(wethToken)), 1.915966050602167855e18);
    }

    function test_maxInvest_reserveToken_withMaxTotalSupply() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);
        uint256 maxTotalSupply = 100_000e18;
        lovToken.setMaxTotalSupply(maxTotalSupply);

        // No token supply no reserves
        // Capped to the remaining space in the spark supply.
        // max 800k, already supplied 407k = 393k remaining space
        (,uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, type(uint256).max);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            // share price = 1, +fees
            assertEq(manager.maxInvest(address(wethToken)), 105_263.157894736842105263e18);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovToken(alice, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            // Almost exactly 10. Aave took a tiny fee.
            (,expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, type(uint256).max);
            // share price > 1, +fees
            assertEq(manager.maxInvest(address(wethToken)), 110_792.797783933518005540e18);
        }

        // Only rebalance a little. A/L is still 11
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18 - 1;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
            assertEq(manager.maxInvest(address(wethToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 1.999999652006238981e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 23.333333333333333332e18;
            uint256 expectedLiabilities = 13.333333150178722270e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxInvest(address(wethToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 100;
            deal(address(wethToken), alice, investAmount, false);
            vm.startPrank(alice);
            wethToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(wethToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.750000024039043032e18, 1.900000000000000007e18, 1.9e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovToken(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(wethToken)), 1);
            exitLovToken(alice, amountOut, alice);
        }

        assertEq(manager.maxInvest(address(wethToken)), 1.915966050602167855e18);
    }

    function test_investQuote_badToken_gives0() public {
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

    function test_investQuote_reserveToken() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            1e18,
            address(wethToken),
            100,
            123
        );

        assertEq(quoteData.fromToken, address(wethToken));
        assertEq(quoteData.fromTokenAmount, 1e18);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 0.999e18);
        assertEq(quoteData.minInvestmentAmount, 0.98901e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 10);
    }

    function test_investWithToken_fail_badToken() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wethToken),
            100,
            123
        );
        quoteData.fromToken = address(wbtcToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wbtcToken)));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_zeroAmount() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wethToken),
            100,
            123
        );
        quoteData.fromTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(AaveErrors.INVALID_AMOUNT));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_success() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wethToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        deal(address(wethToken), address(manager), amount, false);
        uint256 amountOut = manager.investWithToken(alice, quoteData);

        assertEq(amountOut, 0.999e18); // deposit fee
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), amount);
        assertEq(manager.reservesBalance(), amount);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestExit is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    using OrigamiMath for uint256;
    
    function test_maxExit_fail_badAsset() public {
        assertEq(manager.maxExit(alice), 0);
    }

    function test_maxExit_reserveToken() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(0, 500, 0);
        
        // No token supply no reserves
        {
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(wethToken)), 0);
        }

        // with reserves, no liabilities. Capped at total supply (10e18)
        {
            uint256 totalSupply = 20e18;
            uint256 shares = investLovToken(alice, totalSupply / 2);
            assertEq(shares, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(wethToken)), 10e18);
        }

        // Only rebalance a little. A/L is still 11. Still capped at total supply (10e18)
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18 - 1;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 1e18);
            assertEq(manager.maxExit(address(wethToken)), 9.999999999999999998e18);
        }

        // Rebalance down properly
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 23.333333333333333332e18;
            uint256 expectedLiabilities = 13.333333150178722270e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), expectedLiabilities);
            assertEq(manager.maxExit(address(wethToken)), 3.508772154751272623e18);
        }

        {
            vm.startPrank(origamiMultisig);
            manager.setUserALRange(1.45986e18, 5e18);
            manager.setRebalanceALRange(1.45986e18, 5e18);
            doRebalanceUp(2e18, 0, 5);
        }

        // Do a large external borrow to use all the wstETH supply up
        {
            IAavePool pool = borrowLend.aavePool();
            AaveDataTypes.ReserveData memory _reserveData = pool.getReserveData(address(wethToken));

            // Set the borrow cap to the supply cap
            {
                vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
                AaveReserveConfiguration.setBorrowCap(_reserveData.configuration, 800_000); 
                pool.setConfiguration(address(wethToken), _reserveData.configuration);
            }

            // Supply wbtc, borrow weth
            {
                uint256 supplyAmount = 16e8;
                deal(address(wbtcToken), bob, supplyAmount);
                vm.startPrank(bob);
                wbtcToken.approve(address(pool), supplyAmount);
                pool.setUserEMode(SPARK_EMODE_NONE);
                pool.supply(address(wbtcToken), supplyAmount, bob, 0);
                pool.borrow(
                    address(wethToken), 
                    205e18, 
                    uint256(AaveDataTypes.InterestRateMode.VARIABLE), 
                    0,
                    bob
                );
            }

            // Now the max exit is the max amount which can be withdrawn from aave
            // but converted to lovToken shares and with fees
            assertEq(manager.maxExit(address(wethToken)), 5.685684387843108120e18);
        }
    }

    function test_exitQuote_badToken_gives0() public {
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
        assertEq(exitFeeBps[0], 50);
    }

    function test_exitQuote_reserveToken() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = manager.exitQuote(
            1e18,
            address(wethToken),
            100,
            123
        );

        assertEq(quoteData.investmentTokenAmount, 1e18);
        assertEq(quoteData.toToken, address(wethToken));
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, 0.995e18);
        assertEq(quoteData.minToTokenAmount, 0.98505e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], 50);
    }

    function test_exitToToken_fail_badToken() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(wethToken),
            100,
            123
        );

        quoteData.toToken = address(wbtcToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wbtcToken)));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_zeroAmount() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(wethToken),
            100,
            123
        );

        quoteData.investmentTokenAmount = 0;
        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(AaveErrors.INVALID_AMOUNT));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_success() public {
        uint256 investAmount = 1e18;
        uint256 shares = investLovToken(alice, investAmount);
        assertEq(shares, 0.999e18);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            shares,
            address(wethToken),
            100,
            123
        );

        vm.startPrank(address(lovToken));
        (uint256 amountBack, uint256 toBurn) = manager.exitToToken(alice, quoteData, bob);

        assertEq(amountBack, 0.995e18); // 50bps exit fee 
        assertEq(toBurn, shares);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 0.005e18);
        assertEq(manager.reservesBalance(), 0.005e18);
        assertEq(wethToken.balanceOf(bob), amountBack);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestRebalanceDown is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceDown_fail_fresh() public {
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.INVALID_AMOUNT));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_fail_slippage() public {
        uint256 flashLoanAmount = 1e8;
        bytes memory swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: flashLoanAmount
        }));
        deal(address(wethToken), address(swapper), flashLoanAmount, false);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, flashLoanAmount+1, flashLoanAmount));
        manager.rebalanceDown(IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams(
            flashLoanAmount, 
            flashLoanAmount+1, 
            swapData,
            0,
            0
        ));
    }

    function test_rebalanceDown_success_noSupply() public {
        uint256 flashLoanAmount = 1e8;
        uint256 reservesAmount = 28e18;
        bytes memory swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: reservesAmount
        }));
        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams(
            flashLoanAmount, 
            reservesAmount, 
            swapData,
            1.52e18,
            1.53e18
        ));
        (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 28e18);
        assertEq(liabilities, 18.315461106385722146e18);
        assertEq(ratio, 1.528763039999999999e18);
    
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 28e18);
        assertEq(liabilities, 18.315461106385722146e18);
        assertEq(ratio, 1.528763039999999999e18);
    }

    function test_rebalanceDown_fail_al_validation() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);

        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.startPrank(origamiMultisig);

        uint256 expectedActualAl = targetAL - 1; // almost got the target exactly

        // Can't be < minNewAL
        params.minNewAL = uint128(expectedActualAl+1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, expectedActualAl, expectedActualAl+1));
        manager.rebalanceDown(params);

        // Can't be > maxNewAL
        params.minNewAL = uint128(expectedActualAl);
        params.maxNewAL = uint128(expectedActualAl-1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, type(uint128).max, expectedActualAl, expectedActualAl-1));
        manager.rebalanceDown(params);

        // A successful rebalance, just above the real target
        doRebalanceDown(TARGET_AL + 0.0002e18, 0, slippageBps);

        // Now do another rebalance, but we get a 2x BETTER swap when going
        // USDC->DAI
        // Meaning we have more reserves, so A/L is higher than we started out.
        {
            (params, reservesAmount) = rebalanceDownParams(targetAL-0.05e18, slippageBps, 200);

            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: reservesAmount*2
            }));

            deal(address(wethToken), address(swapper), reservesAmount*2, false);
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.750200002678575969e18, 1.766915493550074183e18, 1.734e18));
            manager.rebalanceDown(params);
        }
    }

    function test_rebalanceDown_fail_al_floor() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = rebalanceALRange.floor - 0.001e18;
        uint256 slippageBps = 1;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.469000001877997785e18, 1.47e18));
        manager.rebalanceDown(params);
    }
    
    function test_rebalanceDown_success_withEvent() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(wethToken), address(swapper), reservesAmount, false);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 66.666666666666666667e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.flashLoanAmount),
            type(uint128).max,
            targetAL-1
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666667e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), amount + expectedCollateralAdded);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount);
    }
    
    function test_rebalanceDown_success_al_floor_force() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(uint128(targetAL + 0.01e18), rebalanceALRange.ceiling);
            
        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(wethToken), address(swapper), reservesAmount, false);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.749999999999999999e18, 1.76e18));
        manager.rebalanceDown(params);

        uint256 expectedCollateralAdded = 66.666666666666666667e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralAdded),
            int256(params.flashLoanAmount),
            type(uint128).max,
            targetAL-1
        );
        manager.forceRebalanceDown(params);

        assertEq(manager.reservesBalance(), amount + expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedCollateralAdded);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666667e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), amount + expectedCollateralAdded);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount);
    }

    function test_rebalanceDown_success_withFlashloanFee() public {
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            flProvider.POOL().updateFlashloanPremiums(10 /*bps*/, 0);
            vm.stopPrank();
        }

        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
            
        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        deal(address(wethToken), address(swapper), reservesAmount, false);

        uint256 expectedCollateralSupplied = 66.666666666666666667e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralSupplied),
            int256(params.flashLoanAmount*1.001e18/1e18),
            type(uint128).max,
            1.748251749211389717e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), 116.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 66.733333296702411121e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.733333296702411121e18);
        assertEq(manager.assetToLiabilityRatio(), 1.748251749211389717e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 116.666666666666666667e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount*1.001e18/1e18);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestRebalanceUp is OrigamiLovTokenFlashAndBorrowManagerNotMatchingDecimalsTestBase {
    using OrigamiMath for uint256;

    event Rebalance(
        int256 collateralChange,
        int256 debtChange,
        uint256 alRatioBefore,
        uint256 alRatioAfter
    );

    function test_rebalanceUp_fail_noAaveDebt() public {
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams({
            collateralToWithdraw: 10e18,
            flashLoanAmount: 10e8,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e8
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });
        deal(address(wbtcToken), address(swapper), params.flashLoanAmount, false);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_repayTooMuch() public {
        uint256 amount = 1e18;
        investLovToken(alice, amount);

        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 0.07279824e8);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams({
            collateralToWithdraw: 1e18,
            flashLoanAmount: 10e8,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e8
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });
        deal(address(wbtcToken), address(swapper), params.flashLoanAmount, false);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(wbtcToken), 10e8));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_withdrawMaxCollateral() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 405e18;
            params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
                address(wethToken),
                params.collateralToWithdraw,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );
            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.flashLoanAmount
            }));
            params.minNewAL = 0;
            params.maxNewAL = type(uint128).max;
        }
        params.collateralToWithdraw = type(uint256).max;

        deal(address(wbtcToken), address(swapper), 500e18);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(wethToken), type(uint256).max));
        manager.forceRebalanceUp(params);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_noSurplus() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        uint256 currentDebt = IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend));
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 116.666666666666666667e18);
        assertEq(currentDebt, 3.63991200e8);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 105e18;
            params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
                address(wethToken),
                params.collateralToWithdraw,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );
            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.flashLoanAmount
            }));
            params.minNewAL = 0;
            params.maxNewAL = type(uint128).max;
        }

        deal(address(wbtcToken), address(swapper), 500e8);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(currentDebt),
            targetAL-1,
            type(uint128).max
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 11.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(borrowLend)), 2.09294940e8);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 11.666666666666666667e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_withSurplus() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 116.666666666666666667e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.63991200e8);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 66.5e18;

            params.flashLoanAmount = wEthToWbtcOracle.convertAmount(
                address(wethToken),
                params.collateralToWithdraw,
                IOrigamiOracle.PriceType.SPOT_PRICE,
                OrigamiMath.Rounding.ROUND_UP
            );
            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: params.flashLoanAmount
            }));
            params.minNewAL = 0;
            params.maxNewAL = type(uint128).max;
        }

        deal(address(wbtcToken), address(swapper), 500e8);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));

        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            targetAL-1,
            300.999999999999999400e18
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 50.166666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.166666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.166666666666666667e18);
        assertEq(manager.assetToLiabilityRatio(), 300.999999999999999400e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 50.166666666666666667e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 0.00909978e8);
    }

    function test_rebalanceUp_fail_slippage() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 10, 50);
        params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: params.flashLoanAmount-1
        }));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, params.flashLoanAmount, params.flashLoanAmount-1));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_al_validation() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        uint256 expectedNewAl = targetAL;

        // Can't be < minNewAL
        params.minNewAL = uint128(expectedNewAl+0.0001e18);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, expectedOldAl, 1.800000005274852814e18, expectedNewAl+0.0001e18));
        manager.rebalanceUp(params);

        // Can't be > maxNewAL
        params.minNewAL = uint128(expectedNewAl);
        params.maxNewAL = uint128(expectedNewAl);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, 1.800000005274852814e18, expectedNewAl));
        manager.rebalanceUp(params);

        // Now do another rebalance, but withdraw and extra 2x collateral, and still
        // get the full amount of wbtc when swapped
        // Meaning we withdraw more collateral, so A/L is higher than we started out.
        {
            params = rebalanceUpParams(targetAL, 0, 5000);
            params.collateralToWithdraw = params.collateralToWithdraw*2;
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.749999999999999999e18, 1.733333338412821228e18, 1.749999999999999999e18));
            manager.rebalanceUp(params);
        }
    }

    function test_rebalanceUp_fail_al_ceiling() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = rebalanceALRange.ceiling+1;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, 2.000000007326184468e18, rebalanceALRange.ceiling));
        manager.rebalanceUp(params);
    }
    
    function test_rebalanceUp_success_withEvent() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(manager.reservesBalance(), 116.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 66.666666666666666667e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 66.666666666666666667e18);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            TARGET_AL-1,
            1.800000005274852814e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 112.499999999999999999e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 62.499999816845388937e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 62.499999816845388937e18);
        assertEq(manager.assetToLiabilityRatio(), 1.800000005274852814e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 112.499999999999999999e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.41241749e8);
    }
    
    function test_rebalanceUp_success_al_floor_force() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.5e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, TARGET_AL-1, 2.250000010302446919e18, 2e18));
        manager.rebalanceUp(params);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            TARGET_AL-1,
            2.250000010302446919e18
        );
        manager.forceRebalanceUp(params);
    }

    function test_rebalanceUp_success_withFlashloanFee() public {
        uint128 feeBps = 10;
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            flProvider.POOL().updateFlashloanPremiums(feeBps, 0);
            vm.stopPrank();
        }

        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = 1.748251749211389717e18;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            oldAl,
            1.799875647686546192e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 112.350000082419574978e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 62.420979041984165185e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 62.420979041984165185e18);
        assertEq(manager.assetToLiabilityRatio(), 1.799875647686546192e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 112.350000082419574978e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.40810306e8);
    }

    function test_rebalanceUp_success_surplusUnderThreshold() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        repaySurplusThreshold = 0.0005e8;
        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);

        uint256 expectedSurplus = 0.00045499e8;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(0.22703952e8),
            oldAl,
            1.799760036741835721e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 112.499999999999999999e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 62.508333168494183376e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 62.508333168494183376e18);
        assertEq(manager.assetToLiabilityRatio(), 1.799760036741835721e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), expectedSurplus);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 112.499999999999999999e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.41287248e8);
    }

    function test_rebalanceUp_success_surplusOverThreshold() public {
        uint256 amount = 50e18;
        investLovToken(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        repaySurplusThreshold = 0.0004e8;
        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(0.22749451e8),
            oldAl,
            1.800000005274852814e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 112.499999999999999999e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 62.499999816845388937e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 62.499999816845388937e18);
        assertEq(manager.assetToLiabilityRatio(), 1.800000005274852814e18);

        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(wbtcToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WETH_ADDRESS).balanceOf(address(borrowLend)), 112.499999999999999999e18);
        assertEq(IERC20(SPARK_D_WBTC_ADDRESS).balanceOf(address(borrowLend)), 3.41241749e8);
    }
}
