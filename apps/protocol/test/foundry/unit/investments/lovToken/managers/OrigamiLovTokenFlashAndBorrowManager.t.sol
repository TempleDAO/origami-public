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
import { OrigamiStableChainlinkOracle } from "contracts/common/oracle/OrigamiStableChainlinkOracle.sol";
import { OrigamiWstEthToEthOracle } from "contracts/common/oracle/OrigamiWstEthToEthOracle.sol";
import { DummyLovTokenSwapper } from "contracts/test/investments/lovToken/DummyLovTokenSwapper.sol";
import { Range } from "contracts/libraries/Range.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { LovTokenHelpers } from "test/foundry/libraries/LovTokenHelpers.t.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyOracle } from "contracts/test/common/DummyOracle.sol";
import { OrigamiCrossRateOracle } from "contracts/common/oracle/OrigamiCrossRateOracle.sol";
import { OrigamiAaveV3BorrowAndLend } from "contracts/common/borrowAndLend/OrigamiAaveV3BorrowAndLend.sol";

contract OrigamiLovTokenFlashAndBorrowManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    OrigamiAaveV3FlashLoanProvider internal flProvider;
    IERC20 internal wethToken;
    IERC20 internal stEthToken;
    IERC20 internal wstEthToken;
    OrigamiLovToken internal lovToken;
    OrigamiLovTokenFlashAndBorrowManager internal manager;
    TokenPrices internal tokenPrices;
    DummyLovTokenSwapper internal swapper;
    OrigamiAaveV3BorrowAndLend internal borrowLend;

    IAggregatorV3Interface internal clStEthToEthOracle;
    OrigamiStableChainlinkOracle stEthToEthOracle;
    OrigamiWstEthToEthOracle wstEthToEthOracle;

    Range.Data internal userALRange;
    Range.Data internal rebalanceALRange;

    uint256 internal repaySurplusThreshold = 0;

    address internal constant SPARK_POOL_ADDRESS_PROVIDER = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address internal constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant STETH_ETH_ORACLE = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address internal constant SPARK_A_WSTETH_ADDRESS = 0x12B54025C112Aa61fAce2CDB7118740875A566E9;
    address internal constant SPARK_D_WETH_ADDRESS = 0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d;
    address internal constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint16 internal constant MIN_DEPOSIT_FEE_BPS = 10;
    uint16 internal constant MIN_EXIT_FEE_BPS = 50;
    uint24 internal constant FEE_LEVERAGE_FACTOR = 15e4;
    uint48 internal constant PERFORMANCE_FEE_BPS = 500;

    uint256 internal constant TARGET_AL = 1.1236e18; // 89% LTV

    uint128 internal constant STETH_ETH_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 internal constant STETH_ETH_MIN_THRESHOLD = 0.99e18;
    uint128 internal constant STETH_ETH_MAX_THRESHOLD = 1.01e18;
    uint256 internal constant STETH_ETH_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
    uint8 internal constant SPARK_EMODE_ETH = 1;

    function setUp() public {
        fork("mainnet", 19238000);
        vm.warp(1708056616);
        wethToken = IERC20(WETH_ADDRESS);
        wstEthToken = IERC20(WSTETH_ADDRESS);
        stEthToken = IERC20(STETH_ADDRESS);

        flProvider = new OrigamiAaveV3FlashLoanProvider(SPARK_POOL_ADDRESS_PROVIDER);

        tokenPrices = new TokenPrices(30);
        lovToken = new OrigamiLovToken(
            origamiMultisig, 
            "Origami lovStEth", 
            "lovStEth", 
            PERFORMANCE_FEE_BPS, 
            feeCollector, 
            address(tokenPrices),
            type(uint256).max
        );

        borrowLend = new OrigamiAaveV3BorrowAndLend(
            origamiMultisig,
            address(wstEthToken),
            address(wethToken),
            SPARK_POOL,
            SPARK_EMODE_ETH
        );
        manager = new OrigamiLovTokenFlashAndBorrowManager(
            origamiMultisig, 
            address(wstEthToken), 
            address(wethToken),
            address(stEthToken),
            address(lovToken),
            address(flProvider),
            address(borrowLend)
        );
        swapper = new DummyLovTokenSwapper();

        // Oracles
        {
            clStEthToEthOracle = IAggregatorV3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

            stEthToEthOracle = new OrigamiStableChainlinkOracle(
                origamiMultisig,
                IOrigamiOracle.BaseOracleParams(
                    "stETH/ETH",
                    address(stEthToken),
                    18,
                    address(wethToken),
                    18
                ),
                STETH_ETH_HISTORIC_STABLE_PRICE,
                address(clStEthToEthOracle),
                STETH_ETH_STALENESS_THRESHOLD,
                Range.Data(STETH_ETH_MIN_THRESHOLD, STETH_ETH_MAX_THRESHOLD),
                true,
                true
            );
            wstEthToEthOracle = new OrigamiWstEthToEthOracle(
                IOrigamiOracle.BaseOracleParams(
                    "wstETH/ETH",
                    address(wstEthToken),
                    18,
                    address(wethToken),
                    18
                ),
                address(stEthToken),
                address(stEthToEthOracle)
            );
        }

        vm.startPrank(origamiMultisig);
        borrowLend.setPositionOwner(address(manager));
        lovToken.setManager(address(manager));
        manager.setFeeConfig(MIN_DEPOSIT_FEE_BPS, MIN_EXIT_FEE_BPS, FEE_LEVERAGE_FACTOR);
        manager.setSwapper(address(swapper));
        manager.setOracles(address(wstEthToEthOracle), address(stEthToEthOracle));

        userALRange = Range.Data(1.12e18, 1.16e18);
        rebalanceALRange = Range.Data(1.112e18, 1.18e18);

        manager.setUserALRange(userALRange.floor, userALRange.ceiling);
        manager.setRebalanceALRange(rebalanceALRange.floor, rebalanceALRange.ceiling);

        vm.stopPrank();
    }

    function investLovStEth(address account, uint256 amount) internal returns (uint256 amountOut) {
        doMint(wstEthToken, account, amount);
        vm.startPrank(account);
        wstEthToken.approve(address(lovToken), amount);

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            amount,
            address(wstEthToken),
            0,
            0
        );

        amountOut = lovToken.investWithToken(quoteData);
    }

    function exitLovStEth(address account, uint256 amount, address recipient) internal returns (uint256 amountOut) {
        vm.startPrank(account);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            amount,
            address(wstEthToken),
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

        doMint(wstEthToken, address(swapper), reservesAmount);

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
        params.flashLoanAmount = wstEthToEthOracle.convertAmount(
            address(wstEthToken),
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
        params.flashLoanAmount = wstEthToEthOracle.convertAmount(
            address(wstEthToken),
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

        doMint(wstEthToken, address(swapper), reservesAmount);
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

        params.flashLoanAmount = wstEthToEthOracle.convertAmount(
            address(wstEthToken),
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
        // we would get when converting the collateral [wstETH] to the flashloan asset [wETH].
        // We need to be sure it can be paid off. Any remaining wETH is repaid on the wETH debt in Spark
        params.flashLoanAmount = params.flashLoanAmount.subtractBps(swapSlippageBps, OrigamiMath.Rounding.ROUND_DOWN);

        // When to sweep surplus balances and repay
        params.repaySurplusThreshold = repaySurplusThreshold;

        params.minNewAL = uint128(OrigamiMath.subtractBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        params.maxNewAL = uint128(OrigamiMath.addBps(targetAL, alSlippageBps, OrigamiMath.Rounding.ROUND_UP));
    }

}

contract OrigamiLovTokenFlashAndBorrowManagerTestAdmin is OrigamiLovTokenFlashAndBorrowManagerTestBase {
    event OraclesSet(address indexed debtTokenToReserveTokenOracle, address indexed dynamicFeePriceOracle);
    event SwapperSet(address indexed swapper);
    event FlashLoanProviderSet(address indexed provider);
    event BorrowLendSet(address indexed addr);

    function test_initialization() public {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.lovToken()), address(lovToken));

        assertEq(manager.baseToken(), address(wstEthToken));
        assertEq(manager.reserveToken(), address(wstEthToken));
        assertEq(manager.debtToken(), address(wethToken));
        assertEq(manager.dynamicFeeOracleBaseToken(), address(stEthToken));
        assertEq(address(borrowLend.aavePool()), 0xC13e21B648A5Ee794902342038FF3aDAB66BE987);
        assertEq(address(borrowLend.aaveAToken()), SPARK_A_WSTETH_ADDRESS);
        assertEq(address(borrowLend.aaveDebtToken()), 0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d);
        assertEq(address(manager.flashLoanProvider()), address(flProvider));
        assertEq(address(manager.swapper()), address(swapper));      
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(wstEthToEthOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(stEthToEthOracle));

        (uint64 minDepositFee, uint64 minExitFee, uint64 feeLeverageFactor) = manager.getFeeConfig();
        assertEq(minDepositFee, MIN_DEPOSIT_FEE_BPS);
        assertEq(minExitFee, MIN_EXIT_FEE_BPS);
        assertEq(feeLeverageFactor, FEE_LEVERAGE_FACTOR);

        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.12e18);
        assertEq(ceiling, 1.16e18);

        (floor, ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.112e18);
        assertEq(ceiling, 1.18e18);

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
        assertEq(tokens[0], address(wstEthToken));

        tokens = manager.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(wstEthToken));
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
        assertEq(wstEthToken.allowance(address(manager), alice), type(uint256).max);
        assertEq(wethToken.allowance(address(manager), alice), type(uint256).max);

        vm.expectEmit(address(manager));
        emit SwapperSet(bob);
        manager.setSwapper(bob);
        assertEq(address(manager.swapper()), bob);
        assertEq(wstEthToken.allowance(address(manager), alice), 0);
        assertEq(wstEthToken.allowance(address(manager), bob), type(uint256).max);
        assertEq(wethToken.allowance(address(manager), alice), 0);
        assertEq(wethToken.allowance(address(manager), bob), type(uint256).max);
    }

    function test_setOracleConfig_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setOracles(address(0), address(stEthToEthOracle));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setOracles(address(wstEthToEthOracle), address(0));

        OrigamiWstEthToEthOracle badOracle = new OrigamiWstEthToEthOracle(
            IOrigamiOracle.BaseOracleParams(
                "wstETH/alice",
                address(wstEthToken),
                18,
                alice,
                18
            ),
            address(stEthToken),
            address(stEthToEthOracle)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setOracles(address(badOracle), address(stEthToEthOracle));

        badOracle = new OrigamiWstEthToEthOracle(
            IOrigamiOracle.BaseOracleParams(
                "alice/ETH",
                alice,
                18,
                address(wethToken),
                18
            ),
            address(stEthToken),
            address(stEthToEthOracle)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setOracles(address(badOracle), address(stEthToEthOracle));
    }

    function test_setOracles() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit OraclesSet(address(wstEthToEthOracle), address(stEthToEthOracle));
        manager.setOracles(address(wstEthToEthOracle), address(stEthToEthOracle));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(wstEthToEthOracle));
        assertEq(address(manager.dynamicFeePriceOracle()), address(stEthToEthOracle));

        OrigamiWstEthToEthOracle oracle1 = new OrigamiWstEthToEthOracle(
            IOrigamiOracle.BaseOracleParams(
                "wstETH/ETH",
                address(wstEthToken),
                18,
                address(wethToken),
                18
            ),
            address(stEthToken),
            address(stEthToEthOracle)
        );

        OrigamiWstEthToEthOracle oracle2 = new OrigamiWstEthToEthOracle(
            IOrigamiOracle.BaseOracleParams(
                "stETH/ETH",
                address(stEthToken),
                18,
                address(wethToken),
                18
            ),
            address(stEthToken),
            address(stEthToEthOracle)
        );

        vm.expectEmit(address(manager));
        emit OraclesSet(address(oracle1), address(oracle2));
        manager.setOracles(address(oracle1), address(oracle2));
        assertEq(address(manager.debtTokenToReserveTokenOracle()), address(oracle1));
        assertEq(address(manager.dynamicFeePriceOracle()), address(oracle2));
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

        manager.setUserALRange(1.12e18, 2e18);
        (uint128 floor, uint128 ceiling) = manager.userALRange();
        assertEq(floor, 1.12e18);
        assertEq(ceiling, 2e18);

    }

    function test_setRebalanceAlRange_failValidate() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(Range.InvalidRange.selector, 1.10e18, 2e18));
        manager.setRebalanceALRange(1.10e18, 2e18);

        manager.setRebalanceALRange(1.12e18, 2e18);
        (uint128 floor, uint128 ceiling) = manager.rebalanceALRange();
        assertEq(floor, 1.12e18);
        assertEq(ceiling, 2e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }

    function test_flashLoanCallback_fail_badToken() public {
        vm.startPrank(address(flProvider));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wstEthToken)));
        manager.flashLoanCallback(wstEthToken, 123, 123, bytes(""));
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
        manager.flashLoanCallback(wethToken, 123, 123, params);
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
        manager.flashLoanCallback(wethToken, 123, 123, params);
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
        manager.flashLoanCallback(wethToken, 123, 123, params);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestAccess is OrigamiLovTokenFlashAndBorrowManagerTestBase {
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
        manager.recoverToken(address(wstEthToken), alice, 123);
    }

    function test_access_flashLoanCallback() public {
        expectElevatedAccess();
        manager.flashLoanCallback(wstEthToken, 123, 123, bytes(""));
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestViews is OrigamiLovTokenFlashAndBorrowManagerTestBase {
    function test_reservesBalance() public {
        uint256 amount = 50e18;

        investLovStEth(alice, amount);
        uint256 expectedReserves = amount;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        doRebalanceDown(TARGET_AL, 0, 5);
        expectedReserves = 454.530744336569579289e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), TARGET_AL-1); // almost nailed it, slight rounding diff

        doRebalanceUp(rebalanceALRange.ceiling, 0, 5);
        expectedReserves = 327.777777777777777773e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), rebalanceALRange.ceiling); // nailed it

        uint256 exitAmount = 5e18;
        exitLovStEth(alice, exitAmount, bob);
        expectedReserves = 322.779787020293349391e18;
        assertEq(manager.reservesBalance(), IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)));
        assertEq(manager.reservesBalance(), expectedReserves);
        assertEq(manager.assetToLiabilityRatio(), 1.162007233273056058e18);
        
        assertEq(wstEthToken.balanceOf(bob), 4.997990757484428381e18);
    }

    function test_liabilities_success() public {
        uint256 amount = 50e18;

        investLovStEth(alice, amount);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        doRebalanceDown(TARGET_AL, 0, 5);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 467.986509655154274272e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 404.530744336569579289e18); // weth / stEthToEthPrice / wstEthToStEthPrice
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022522e18); // weth / 1.0 / wstEthToStEthPrice

        doRebalanceUp(rebalanceALRange.ceiling, 0, 5);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 321.350736629872601532e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 277.777777777777777662e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 277.694424123133888682e18);

        // Exits don't affect liabilities
        uint256 exitAmount = 5e18;
        exitLovStEth(alice, exitAmount, bob);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 321.350736629872601532e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 277.777777777777777662e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 277.694424123133888682e18);
    }

    function test_liabilities_zeroDebt() public {
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
    }

    function test_liabilities_withDebt_isPricingToken() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 404.530744336569579289e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022522e18);
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
            OrigamiStableChainlinkOracle oOne = new OrigamiStableChainlinkOracle(
                origamiMultisig, 
                IOrigamiOracle.BaseOracleParams(
                    "ONE/ONE", 
                    address(wethToken),
                    18,
                    address(wethToken),
                    18
                ),
                1e18, 
                address(clOne), 
                365 days, 
                Range.Data(1e18, 1e18),
                false,
                true
            );

            OrigamiCrossRateOracle ethToWstEth = new OrigamiCrossRateOracle(
                IOrigamiOracle.BaseOracleParams(
                    "ETH/wstETH",
                    address(wethToken),
                    18,
                    address(wstEthToken),
                    18
                ),
                address(oOne), 
                address(wstEthToEthOracle),
                address(0)
            );

            manager.setOracles(address(ethToWstEth), address(stEthToEthOracle));
        }

        uint256 amount = 50e18;
        investLovStEth(alice, amount);
        doRebalanceDown(TARGET_AL, 0, 5);

        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 404.530744336569579360e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022552e18);
    }

    function test_getDynamicFeesBps() public {
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 46);
        assertEq(exitFee, 50);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestInvest is OrigamiLovTokenFlashAndBorrowManagerTestBase {
    using OrigamiMath for uint256;
    
    function test_maxInvest_fail_badAsset() public {
        assertEq(manager.maxInvest(alice), 0);
    }

    function test_maxInvest_reserveToken() public {
        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(500, 0, FEE_LEVERAGE_FACTOR);

        // No token supply no reserves
        // Capped to the remaining space in the spark supply.
        // max 800k, already supplied 407k = 393k remaining space
        (, uint256 expectedAvailable) = borrowLend.availableToSupply();
        {
            assertEq(expectedAvailable, 109_440.764612771907497262e18);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxInvest(address(wstEthToken)), expectedAvailable);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovStEth(alice, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            // Almost exactly 10. Aave took a tiny fee.
            (, expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, 109_430.764603401718130390e18);
            assertEq(manager.maxInvest(address(wstEthToken)), expectedAvailable);
        }

        // Only rebalance a little. A/L is still 11
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.999699926843282e18);
            assertEq(manager.maxInvest(address(wstEthToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 2.944983818770226536e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 90.906148867313915858e18;
            uint256 expectedLiabilities = 80.906148867313915857e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 80.881871103825404504e18);
            assertEq(manager.maxInvest(address(wstEthToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 100;
            doMint(wstEthToken, alice, investAmount);
            vm.startPrank(alice);
            wstEthToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(wstEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.1236e18, 1.160000000000000001e18, 1.16e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovStEth(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(wstEthToken)), 0);
            exitLovStEth(alice, amountOut, alice);
        }

        // Do an external huge deposit into spark to max out the available supply, except 1 eth
        {
            (, uint256 available) = borrowLend.availableToSupply();
            uint256 extAmount = available - 1e18;
            deal(address(wstEthToken), bob, extAmount);
            vm.startPrank(bob);
            wstEthToken.approve(address(borrowLend.aavePool()), extAmount);
            borrowLend.aavePool().supply(address(wstEthToken), extAmount, bob, 0);
        }

        assertEq(manager.maxInvest(address(wstEthToken)), 1e18);
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
            assertEq(expectedAvailable, 109_440.764612771907497262e18);
            assertEq(manager.reservesBalance(), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            // share price = 1, +fees
            assertEq(manager.maxInvest(address(wstEthToken)), 105_263.157894736842105263e18);
        }

        // with reserves, no liabilities
        // available drops by 10
        {
            investLovStEth(alice, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            
            // Almost exactly 10. Aave took a tiny fee.
            (,expectedAvailable) = borrowLend.availableToSupply();
            assertEq(expectedAvailable, 109_430.764603401718130390e18);
            // share price > 1, +fees
            assertEq(manager.maxInvest(address(wstEthToken)), 109_430.764603401718130390e18);
        }

        // Only rebalance a little. A/L is still 11
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.999699926843282e18);
            assertEq(manager.maxInvest(address(wstEthToken)), 0);
        }

        // Rebalance down properly
        uint256 expectedMaxInvest = 2.944983818770226536e18;
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 90.906148867313915858e18;
            uint256 expectedLiabilities = 80.906148867313915857e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 80.881871103825404504e18);
            assertEq(manager.maxInvest(address(wstEthToken)), expectedMaxInvest);
        }

        {
            uint256 investAmount = expectedMaxInvest + 100;
            doMint(wstEthToken, alice, investAmount);
            vm.startPrank(alice);
            wstEthToken.approve(address(lovToken), investAmount);

            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                investAmount,
                address(wstEthToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.1236e18, 1.160000000000000001e18, 1.16e18));           
            lovToken.investWithToken(quoteData);
        }

        // Can invest with that amount
        {
            uint256 amountOut = investLovStEth(alice, expectedMaxInvest);
            assertEq(manager.maxInvest(address(wstEthToken)), 0);
            exitLovStEth(alice, amountOut, alice);
        }

        // Do an external huge deposit into spark to max out the available supply, except 1 eth
        {
            (,uint256 available) = borrowLend.availableToSupply();
            uint256 extAmount = available - 1e18;
            deal(address(wstEthToken), bob, extAmount);
            vm.startPrank(bob);
            wstEthToken.approve(address(borrowLend.aavePool()), extAmount);
            borrowLend.aavePool().supply(address(wstEthToken), extAmount, bob, 0);
        }

        assertEq(manager.maxInvest(address(wstEthToken)), 1e18);
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
        assertEq(investFeeBps[0], 46);
    }

    function test_investQuote_reserveToken() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = manager.investQuote(
            1e18,
            address(wstEthToken),
            100,
            123
        );

        assertEq(quoteData.fromToken, address(wstEthToken));
        assertEq(quoteData.fromTokenAmount, 1e18);
        assertEq(quoteData.maxSlippageBps, 100);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, 0.9954e18);
        assertEq(quoteData.minInvestmentAmount, 0.985446e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], 46);
    }

    function test_investWithToken_fail_badToken() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wstEthToken),
            100,
            123
        );
        quoteData.fromToken = address(wethToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wethToken)));
        manager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_zeroAmount() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wstEthToken),
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
            address(wstEthToken),
            100,
            123
        );
        vm.startPrank(address(lovToken));
        doMint(wstEthToken, address(manager), amount);
        uint256 amountOut = manager.investWithToken(alice, quoteData);

        assertEq(amountOut, 0.9954e18); // deposit fee
        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), amount);
        assertEq(manager.reservesBalance(), amount);
    }

    function test_investWithToken_success_aaveUpstreamPolicy() public {
        uint256 amount = 1e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = manager.investQuote(
            amount,
            address(wstEthToken),
            100,
            123
        );

        // Lower the upstream LTV
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            AaveDataTypes.EModeCategory memory catData = borrowLend.aavePool().getEModeCategoryData(SPARK_EMODE_ETH);
            catData.ltv = 8900;
            borrowLend.aavePool().configureEModeCategory(SPARK_EMODE_ETH, catData);
        }

        // The invest still works, as this is lowering the LTV anyway
        vm.startPrank(address(lovToken));
        doMint(wstEthToken, address(manager), amount);
        uint256 amountOut = manager.investWithToken(alice, quoteData);

        assertEq(amountOut, 0.9954e18); // deposit fee
        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), amount);
        assertEq(manager.reservesBalance(), amount);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestExit is OrigamiLovTokenFlashAndBorrowManagerTestBase {
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
            assertEq(manager.maxExit(address(wstEthToken)), 0);
        }

        // with reserves, no liabilities. Capped at total supply (10e18)
        {
            uint256 totalSupply = 20e18;
            uint256 shares = investLovStEth(alice, totalSupply / 2);
            assertEq(shares, 10e18);
            assertEq(manager.reservesBalance(), 10e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
            assertEq(manager.maxExit(address(wstEthToken)), 10e18);
        }

        // Only rebalance a little. A/L is still 11. Still capped at total supply (10e18)
        {
            doRebalanceDownFor(1e18, 0);
            uint256 expectedReserves = 10e18 + 1e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 1e18);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.999699926843282e18);
            assertEq(manager.maxExit(address(wstEthToken)), 10e18);
        }

        // Rebalance down properly
        {
            uint256 targetAl = TARGET_AL;
            doRebalanceDown(targetAl, 0, 50);
            uint256 expectedReserves = 90.906148867313915858e18;
            uint256 expectedLiabilities = 80.906148867313915857e18;
            assertEq(manager.reservesBalance(), expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 80.881871103825404504e18);
            assertEq(manager.maxExit(address(wstEthToken)), 0.306591722023505365e18);
        }

        {
            vm.startPrank(origamiMultisig);
            manager.setUserALRange(1.111111112e18, 2e18);
            manager.setRebalanceALRange(1.111111112e18, 2e18);
            doRebalanceUp(1.5e18, 0, 5);
        }

        // Do a large external borrow to use all the wstETH supply up
        {
            IAavePool pool = borrowLend.aavePool();
            AaveDataTypes.ReserveData memory _reserveData = pool.getReserveData(address(wstEthToken));

            // Set the borrow cap to the supply cap
            {
                vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
                AaveReserveConfiguration.setBorrowCap(_reserveData.configuration, 800_000); 
                pool.setConfiguration(address(wstEthToken), _reserveData.configuration);
            }

            // Supply weth, borrow wstEth
            {
                uint256 supplyAmount = 600_000e18;
                deal(address(wethToken), bob, supplyAmount);
                vm.startPrank(bob);
                wethToken.approve(address(pool), supplyAmount);
                pool.setUserEMode(SPARK_EMODE_ETH);
                pool.supply(address(wethToken), supplyAmount, bob, 0);
                pool.borrow(
                    address(wstEthToken), 
                    406_454e18, 
                    uint256(AaveDataTypes.InterestRateMode.VARIABLE), 
                    0,
                    bob
                );
            }

            // Now the max exit is the max amount which can be withdrawn from aave
            // but converted to lovStEth shares and with fees
            assertEq(manager.maxExit(address(wstEthToken)), 8.187134484210526332e18);
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
            address(wstEthToken),
            100,
            123
        );

        assertEq(quoteData.investmentTokenAmount, 1e18);
        assertEq(quoteData.toToken, address(wstEthToken));
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
            address(wstEthToken),
            100,
            123
        );

        quoteData.toToken = address(wethToken);
        vm.startPrank(address(lovToken));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(wethToken)));
        manager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_zeroAmount() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            1e18,
            address(wstEthToken),
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
        uint256 shares = investLovStEth(alice, investAmount);
        assertEq(shares, 0.9954e18);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            shares,
            address(wstEthToken),
            100,
            123
        );

        vm.startPrank(address(lovToken));
        (uint256 amountBack, uint256 toBurn) = manager.exitToToken(alice, quoteData, bob);

        assertEq(amountBack, 0.995e18); // 50bps exit fee 
        assertEq(toBurn, shares);
        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 0.005e18);
        assertEq(manager.reservesBalance(), 0.005e18);
        assertEq(wstEthToken.balanceOf(bob), amountBack);
    }

    function test_exitToToken_fail_aaveUpstreamPolicy() public {
        uint256 investAmount = 1e18;
        uint256 shares = investLovStEth(alice, investAmount);

        doRebalanceDown(TARGET_AL, 20, 20);

        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = manager.exitQuote(
            shares,
            address(wstEthToken),
            100,
            123
        );

        // Lower the upstream LTV
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            AaveDataTypes.EModeCategory memory catData = borrowLend.aavePool().getEModeCategoryData(SPARK_EMODE_ETH);
            catData.ltv = 8000;
            borrowLend.aavePool().configureEModeCategory(SPARK_EMODE_ETH, catData);
        }

        vm.startPrank(address(lovToken));
        vm.expectRevert(bytes(AaveErrors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
        manager.exitToToken(alice, quoteData, bob);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestRebalanceDown is OrigamiLovTokenFlashAndBorrowManagerTestBase {
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
        doMint(wstEthToken, address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.INVALID_AMOUNT));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_fail_slippage() public {
        uint256 flashLoanAmount = 10e18;
        bytes memory swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: flashLoanAmount
        }));
        doMint(wstEthToken, address(swapper), flashLoanAmount);

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
        uint256 flashLoanAmount = 10e18;
        bytes memory swapData = abi.encode(DummyLovTokenSwapper.SwapData({
            buyTokenAmount: flashLoanAmount
        }));
        doMint(wstEthToken, address(swapper), flashLoanAmount);

        vm.startPrank(origamiMultisig);
        manager.rebalanceDown(IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams(
            flashLoanAmount, 
            flashLoanAmount, 
            swapData,
            1.15e18,
            1.16e18
        ));
        (uint256 assets, uint256 liabilities, uint256 ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 10e18);
        assertEq(liabilities, 8.644068493227648519e18);
        assertEq(ratio, 1.156862651867541365e18);
    
        (assets, liabilities, ratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE);
        assertEq(assets, 10e18);
        assertEq(liabilities, 8.641474640307999090e18);
        assertEq(ratio, 1.157209899495068170e18);
    }

    function test_rebalanceDown_fail_al_validation() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);

        doMint(wstEthToken, address(swapper), reservesAmount);

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

        // Now do another rebalance, but we get a 20% BETTER swap when going
        // USDC->DAI
        // Meaning we have more reserves, so A/L is higher than we started out.
        {
            (params, reservesAmount) = rebalanceDownParams(targetAL, slippageBps, 200);

            params.swapData = abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: reservesAmount*1.2e18/1e18
            }));
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, 1.123799999999999999e18, 1.123923101777059773e18, 1.123799999999999999e18));
            manager.rebalanceDown(params);
        }
    }

    function test_rebalanceDown_fail_al_floor() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = rebalanceALRange.floor;
        uint256 slippageBps = 0;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        doMint(wstEthToken, address(swapper), reservesAmount);

        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.111999999999999999e18, 1.112e18));
        manager.rebalanceDown(params);
    }

    function test_rebalanceDown_fail_aaveUpstreamPolicy() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = rebalanceALRange.floor+0.0001e18;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        doMint(wstEthToken, address(swapper), reservesAmount);

        // Lower the upstream LTV
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            AaveDataTypes.EModeCategory memory catData = borrowLend.aavePool().getEModeCategoryData(SPARK_EMODE_ETH);
            catData.ltv = 8900;
            borrowLend.aavePool().configureEModeCategory(SPARK_EMODE_ETH, catData);
        }

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
        manager.rebalanceDown(params);
    }
    
    function test_rebalanceDown_success_withEvent() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        vm.startPrank(origamiMultisig);
        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        doMint(wstEthToken, address(swapper), reservesAmount);

        assertEq(manager.reservesBalance(), amount);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);

        uint256 expectedCollateralAdded = 404.530744336569579289e18;
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
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022522e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), amount + expectedCollateralAdded);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount);
    }
    
    function test_rebalanceDown_success_al_floor_force() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
        manager.setRebalanceALRange(uint128(targetAL + 0.01e18), rebalanceALRange.ceiling);
            
        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        doMint(wstEthToken, address(swapper), reservesAmount);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, type(uint128).max, 1.123599999999999999e18, 1.1336e18));
        manager.rebalanceDown(params);

        uint256 expectedCollateralAdded = 404.530744336569579289e18;
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
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022522e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL-1);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), amount + expectedCollateralAdded);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount);
    }

    function test_rebalanceDown_success_withFlashloanFee() public {
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            flProvider.POOL().updateFlashloanPremiums(10 /*bps*/, 0);
            vm.stopPrank();
        }

        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;

        vm.startPrank(origamiMultisig);
            
        (IOrigamiLovTokenFlashAndBorrowManager.RebalanceDownParams memory params, uint256 reservesAmount) = rebalanceDownParams(targetAL, slippageBps, slippageBps);
        doMint(wstEthToken, address(swapper), reservesAmount);

        uint256 expectedCollateralSupplied = 404.530744336569579289e18;
        vm.expectEmit(address(manager));
        emit Rebalance(
            int256(expectedCollateralSupplied),
            int256(params.flashLoanAmount*1.001e18/1e18),
            type(uint128).max,
            1.122477522477522477e18
        );
        manager.rebalanceDown(params);

        assertEq(manager.reservesBalance(), 454.530744336569579289e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 404.935275080906148868e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.813764874646149544e18);
        assertEq(manager.assetToLiabilityRatio(), 1.122477522477522477e18);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 454.530744336569579289e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), params.flashLoanAmount*1.001e18/1e18);
    }
}

contract OrigamiLovTokenFlashAndBorrowManagerTestRebalanceUp is OrigamiLovTokenFlashAndBorrowManagerTestBase {
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
            flashLoanAmount: 10e18,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e18
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });

        vm.startPrank(origamiMultisig);
        vm.expectRevert(bytes(AaveErrors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_repayTooMuch() public {
        uint256 amount = 1e18;
        investLovStEth(alice, amount);

        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 9.359730193103085485e18);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams({
            collateralToWithdraw: 1e18, //10e18,
            flashLoanAmount: 10e18,
            swapData: abi.encode(DummyLovTokenSwapper.SwapData({
                buyTokenAmount: 10e18
            })),
            repaySurplusThreshold: 0,
            minNewAL: 0,
            maxNewAL: 10e18
        });

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(wethToken), 10e18));
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_fail_withdrawMaxCollateral() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        doRebalanceDown(TARGET_AL, 0, 50);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 405e18;
            params.flashLoanAmount = wstEthToEthOracle.convertAmount(
                address(wstEthToken),
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

        deal(address(wethToken), address(swapper), 500e18);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(wstEthToken), type(uint256).max));
        manager.forceRebalanceUp(params);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_noSurplus() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        uint256 currentDebt = IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend));
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 454.530744336569579289e18);
        assertEq(currentDebt, 467.986509655154274272e18);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 405e18;
            params.flashLoanAmount = wstEthToEthOracle.convertAmount(
                address(wstEthToken),
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

        deal(address(wethToken), address(swapper), 500e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(currentDebt),
            targetAL-1,
            type(uint128).max
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 49.530744336569579290e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0);
        assertEq(manager.assetToLiabilityRatio(), type(uint128).max);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(borrowLend)), 0.542864351199979363e18);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 49.530744336569579290e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 0);
    }

    function test_rebalanceUp_success_forceRepayTooMuch_withSurplus() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        doRebalanceDown(TARGET_AL, 0, 50);

        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 454.530744336569579289e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 467.986509655154274272e18);

        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params;
        {
            params.collateralToWithdraw = 404.5e18;

            params.flashLoanAmount = wstEthToEthOracle.convertAmount(
                address(wstEthToken),
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

        deal(address(wethToken), address(swapper), 500e18);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));

        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            targetAL-1,
            1_627.315789473702684703e18
        );
        manager.forceRebalanceUp(params);

        assertEq(manager.reservesBalance(), 50.030744336569579289e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 0.030744336569578939e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 0.030735111019453304e18);
        assertEq(manager.assetToLiabilityRatio(), 1_627.315789473702684703e18);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 50.030744336569579289e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 0.035566974733791320e18);
    }

    function test_rebalanceUp_fail_slippage() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

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
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        uint256 expectedNewAl = targetAL;

        // Can't be < minNewAL
        params.minNewAL = uint128(expectedNewAl+1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, expectedOldAl, expectedNewAl, expectedNewAl+1));
        manager.rebalanceUp(params);

        // Can't be > maxNewAL
        params.minNewAL = uint128(expectedNewAl);
        params.maxNewAL = uint128(expectedNewAl-1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, expectedNewAl, expectedNewAl-1));
        manager.rebalanceUp(params);

        // Now do another rebalance, but withdraw and extra 20% collateral, and still
        // get the full amount of weth when swapped
        // Meaning we withdraw more collateral, so A/L is higher than we started out.
        {
            params = rebalanceUpParams(targetAL, 0, 5000);
            params.collateralToWithdraw = params.collateralToWithdraw*1.2e18/1e18;
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooLow.selector, 1.123599999999999999e18, 1.092693851132686084e18, 1.123599999999999999e18));
            manager.rebalanceUp(params);
        }
    }

    function test_rebalanceUp_fail_al_ceiling() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 expectedOldAl = targetAL - 1; // almost got the target exactly

        targetAL = rebalanceALRange.ceiling+1;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, expectedOldAl, targetAL, rebalanceALRange.ceiling));
        manager.rebalanceUp(params);
    }
    
    function test_rebalanceUp_success_aaveUpstreamPolicy() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        // Lower the upstream LTV
        {
            vm.startPrank(IPoolAddressesProvider(SPARK_POOL_ADDRESS_PROVIDER).getPoolConfigurator());
            AaveDataTypes.EModeCategory memory catData = borrowLend.aavePool().getEModeCategoryData(SPARK_EMODE_ETH);
            catData.ltv = 8000;
            borrowLend.aavePool().configureEModeCategory(SPARK_EMODE_ETH, catData);
        }

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 10, 50);

        vm.startPrank(origamiMultisig);
        // A rebalance up is still ok as it improves the position
        manager.rebalanceUp(params);
    }

    function test_rebalanceUp_success_withEvent() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        assertEq(manager.reservesBalance(), 454.530744336569579289e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 404.530744336569579289e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 404.409355519127022522e18);

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            TARGET_AL-1,
            targetAL
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 338.018433179723502301e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 288.018433179723502200e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 287.932006579286290124e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 338.018433179723502301e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 333.197768395029195156e18);
    }
    
    function test_rebalanceUp_success_al_floor_force() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);

        targetAL = TARGET_AL + 0.1e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLovTokenManager.ALTooHigh.selector, TARGET_AL-1, targetAL, 1.18e18));
        manager.rebalanceUp(params);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            TARGET_AL-1,
            targetAL
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
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = 1.122477522477522477e18;

        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 0, 50);

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount + 1),
            oldAl,
            1.173110829265901134e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 335.283656212250011184e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 285.807314916750736071e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 285.721551813550571054e18);
        assertEq(manager.assetToLiabilityRatio(), 1.173110829265901134e18);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 335.283656212250011184e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 330.639808257733769232e18);
    }

    function test_rebalanceUp_success_surplusUnderThreshold() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        repaySurplusThreshold = 0.3e18;
        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);

        uint256 expectedSurplus = 0.269577482520250159e18;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount),
            oldAl,
            1.172651253031527890e18
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 338.018433179723502301e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 288.251457802037194354e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 288.164961277165971589e18);
        assertEq(manager.assetToLiabilityRatio(), 1.172651253031527890e18);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), expectedSurplus);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 338.018433179723502301e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 333.467345877549445314e18);
    }

    function test_rebalanceUp_success_surplusOverThreshold() public {
        uint256 amount = 50e18;
        investLovStEth(alice, amount);

        uint256 targetAL = TARGET_AL;
        uint256 slippageBps = 20;
        doRebalanceDown(TARGET_AL, slippageBps, slippageBps);
        uint256 oldAl = targetAL-1;

        repaySurplusThreshold = 0.25e18;
        targetAL = TARGET_AL + 0.05e18;
        IOrigamiLovTokenFlashAndBorrowManager.RebalanceUpParams memory params = rebalanceUpParams(targetAL, 20, 50);

        uint256 expectedSurplus = 0.269577482520250159e18;

        vm.expectEmit(address(manager));
        emit Rebalance(
            -int256(params.collateralToWithdraw),
            -int256(params.flashLoanAmount + expectedSurplus),
            oldAl,
            targetAL
        );
        manager.rebalanceUp(params);

        assertEq(manager.reservesBalance(), 338.018433179723502301e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), 288.018433179723502200e18);
        assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), 287.932006579286290124e18);
        assertEq(manager.assetToLiabilityRatio(), targetAL);

        assertEq(wstEthToken.balanceOf(address(manager)), 0);
        assertEq(wethToken.balanceOf(address(manager)), 0);
        assertEq(IERC20(SPARK_A_WSTETH_ADDRESS).balanceOf(address(borrowLend)), 338.018433179723502301e18);
        assertEq(IERC20(SPARK_D_WETH_ADDRESS).balanceOf(address(borrowLend)), 333.197768395029195156e18);
    }
}
