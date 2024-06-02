pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiLovTokenTestBase } from "test/foundry/unit/investments/lovToken/OrigamiLovTokenBase.t.sol";

import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { IOrigamiOTokenManager } from "contracts/interfaces/investments/IOrigamiOTokenManager.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiOracle } from "contracts/interfaces/common/oracle/IOrigamiOracle.sol";
import { OrigamiLovToken } from "contracts/investments/lovToken/OrigamiLovToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

contract OrigamiLovTokenTestAdmin is OrigamiLovTokenTestBase {
    event ManagerSet(address indexed manager);
    event FeeCollectorSet(address indexed feeCollector);
    event TokenPricesSet(address indexed tokenPrices);
    event MaxTotalSupplySet(uint256 maxTotalSupply);

    function test_initialization() public {
        assertEq(lovToken.owner(), origamiMultisig);
        assertEq(address(lovToken.manager()), address(manager));

        assertEq(address(lovToken.baseToken()), address(sDaiToken));
        assertEq(address(lovToken.reserveToken()), address(sDaiToken));
        address[] memory tokens = lovToken.acceptedInvestTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(daiToken));
        assertEq(tokens[1], address(sDaiToken));

        tokens = lovToken.acceptedExitTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(daiToken));
        assertEq(tokens[1], address(sDaiToken));

        assertEq(lovToken.areInvestmentsPaused(), false);
        assertEq(lovToken.areExitsPaused(), false);
        assertEq(lovToken.reservesPerShare(), 1e18);
        assertEq(lovToken.totalReserves(), 0);
        (uint256 assets, uint256 liabilities, uint256 ratio) = lovToken.assetsAndLiabilities();
        assertEq(assets, 0);
        assertEq(liabilities, 0);
        assertEq(ratio, type(uint128).max);
        assertEq(lovToken.effectiveExposure(), type(uint128).max);
        (uint128 floor, uint128 ceiling) = lovToken.userALRange();
        assertEq(floor, 1.001e18);
        assertEq(ceiling, type(uint128).max);
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 20);
        assertEq(exitFee, 50);
        assertEq(lovToken.annualPerformanceFeeBps(), 500);
        assertEq(lovToken.feeCollector(), feeCollector);
        assertEq(lovToken.lastPerformanceFeeTime(), 1);
        assertEq(lovToken.maxTotalSupply(), MAX_TOTAL_SUPPLY);

        assertEq(address(lovToken.tokenPrices()), address(tokenPrices));
    }

    function test_constructor_fail() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiLovToken(
            origamiMultisig,
            "Origami LOV TOKEN",
            "lovToken",
            10_001,
            feeCollector,
            address(0),
            0
        );
    }

    function test_setManager_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lovToken.setManager(address(0));
    }

    function test_setManager_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit ManagerSet(alice);
        lovToken.setManager(alice);
        assertEq(address(lovToken.manager()), alice);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lovToken.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit FeeCollectorSet(alice);
        lovToken.setFeeCollector(alice);
        assertEq(address(lovToken.feeCollector()), alice);
    }

    function test_paused() public {
        assertEq(lovToken.areInvestmentsPaused(), false);
        assertEq(lovToken.areExitsPaused(), false);

        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        assertEq(lovToken.areInvestmentsPaused(), true);
        assertEq(lovToken.areExitsPaused(), false);

        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        assertEq(lovToken.areInvestmentsPaused(), false);
        assertEq(lovToken.areExitsPaused(), true);
    }

    function test_setTokenPrices_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lovToken.setTokenPrices(address(0));
    }

    function test_setTokenPrices_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit TokenPricesSet(alice);
        lovToken.setTokenPrices(alice);
        assertEq(address(lovToken.tokenPrices()), alice);
    }

    function test_setMaxTotalSupply_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit MaxTotalSupplySet(100);
        lovToken.setMaxTotalSupply(100);
        assertEq(lovToken.maxTotalSupply(), 100);
    }
}

contract OrigamiLovTokenTestAccess is OrigamiLovTokenTestBase {
    function test_access_setManager() public {
        expectElevatedAccess();
        lovToken.setManager(alice);
    }

    function test_access_setAnnualPerformanceFee() public {
        expectElevatedAccess();
        lovToken.setAnnualPerformanceFee(123);
    }

    function test_access_setFeeCollector() public {
        expectElevatedAccess();
        lovToken.setFeeCollector(alice);
    }

    function test_access_collectPerformanceFees() public {
        expectElevatedAccess();
        lovToken.collectPerformanceFees();
    }

    function test_access_setTokenPrices() public {
        expectElevatedAccess();
        lovToken.setTokenPrices(alice);
    }

    function test_access_setMaxTotalSupply() public {
        expectElevatedAccess();
        lovToken.setMaxTotalSupply(100);
    }
}

contract OrigamiLovTokenTestViews is OrigamiLovTokenTestBase {
    using OrigamiMath for uint256;
    
    function test_sharesToReserves() public {
        // No supply
        assertEq(lovToken.sharesToReserves(5e18), 5e18);

        // With supply
        investWithSDai(20e18, alice);
        assertEq(lovToken.sharesToReserves(5e18), 5.010020040080160320e18);

        // After rebalance
        doRebalanceDown(1.11e18);

        {
            uint256 _expectedReserves = 201.818181818181818182e18;
            uint256 _expectedLiabilities = 181.818181818181818182e18;
            assertEq(manager.reservesBalance(), _expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedReserves - _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedReserves - _expectedLiabilities);
            assertEq(lovToken.sharesToReserves(5e18), 5.010020040080160320e18);
        }
    }

    function test_reservesToShares() public {
        // No supply
        assertEq(lovToken.reservesToShares(5e18), 5e18);
        assertEq(lovToken.reservesPerShare(), 1e18);

        // With supply
        investWithSDai(20e18, alice);
        assertEq(lovToken.reservesToShares(5e18), 4.99e18);
        assertEq(lovToken.reservesPerShare(), 1.002004008016032064e18);

        // After rebalance
        doRebalanceDown(1.11e18);
        assertEq(lovToken.reservesToShares(5e18), 4.99e18);
        assertEq(lovToken.reservesPerShare(), 1.002004008016032064e18);

        {
            uint256 _expectedReserves = 201.818181818181818182e18;
            uint256 _expectedLiabilities = 181.818181818181818182e18;
            assertEq(manager.reservesBalance(), _expectedReserves);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedLiabilities);
            assertEq(manager.liabilities(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), _expectedReserves - _expectedLiabilities);
            assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), _expectedReserves - _expectedLiabilities);
            assertEq(lovToken.sharesToReserves(5e18), 5.010020040080160320e18);
        }
    }

    function test_totalReserves() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        doRebalanceDown(1.11e18);

        uint256 actualReserves = lovToken.totalReserves();
        assertEq(actualReserves, 95_238.095238095238095238e18);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.SPOT_PRICE), actualReserves);
        assertEq(manager.userRedeemableReserves(IOrigamiOracle.PriceType.HISTORIC_PRICE), actualReserves);
    }

    function test_assetsAndLiabilities() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        doRebalanceDown(1.11e18);

        (uint256 assets, uint256 liabilities, uint256 ratio) = lovToken.assetsAndLiabilities();
        (uint256 massets, uint256 mliabilities, uint256 mratio) = manager.assetsAndLiabilities(IOrigamiOracle.PriceType.SPOT_PRICE);
        assertEq(assets, 961_038.961038961038961038e18);
        assertEq(liabilities, 865_800.86580086580086580e18);
        assertEq(ratio, 1.11e18);
        assertEq(assets, massets);
        assertEq(liabilities, mliabilities);
        assertEq(ratio, mratio);
    }

    function test_effectiveExposure() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        doRebalanceDown(1.11e18);

        uint256 ee = lovToken.effectiveExposure();
        assertEq(ee, 10.09090909090909091e18);
        assertEq(manager.effectiveExposure(IOrigamiOracle.PriceType.SPOT_PRICE), ee);
    }

    function test_userALRange() public {
        (uint128 floor, uint128 ceiling) = lovToken.userALRange();
        (uint128 mfloor, uint128 mceiling) = manager.userALRange();
        assertEq(floor, 1.001e18);
        assertEq(ceiling, type(uint128).max);
        assertEq(floor, mfloor);
        assertEq(ceiling, mceiling);
    }

    function test_getDynamicFeesBps() public {
        (uint256 depositFee, uint256 exitFee) = lovToken.getDynamicFeesBps();
        assertEq(depositFee, 20);
        assertEq(exitFee, 50);
        (uint256 managerDepositFee, uint256 managerExitFee) = manager.getDynamicFeesBps();
        assertEq(depositFee, managerDepositFee);
        assertEq(exitFee, managerExitFee);
    }
}

contract OrigamiLovTokenTestInvest is OrigamiLovTokenTestBase {
    using OrigamiMath for uint256;
    event Invested(address indexed user, uint256 fromTokenAmount, address indexed fromToken, uint256 investmentAmount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_investWithNative_failure() public {
        IOrigamiInvestment.InvestQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiInvestment.Unsupported.selector));
        lovToken.investWithNative(quoteData);
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_maxInvest() public {
        assertEq(lovToken.maxInvest(address(daiToken)), 10_020_040.080160320641282565e18);
    }

    function test_investQuote_success_depositAsset() public {
        uint256 sharePrice = bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = lovToken.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 20;
        uint256 expectedShares = (depositAmount * 1e18 / sharePrice).subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(quoteData.fromToken, address(daiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, expectedShares);
        assertEq(quoteData.minInvestmentAmount, expectedShares.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], expectedFeeBps);
    }

    function test_investQuote_success_reserveAsset() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = lovToken.investQuote(
            depositAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 20;
        uint256 expectedShares = depositAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN);

        assertEq(quoteData.fromToken, address(sDaiToken));
        assertEq(quoteData.fromTokenAmount, depositAmount);
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedInvestmentAmount, expectedShares);
        assertEq(quoteData.minInvestmentAmount, expectedShares.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(investFeeBps.length, 1);
        assertEq(investFeeBps[0], expectedFeeBps);
    }

    function test_investWithToken_failZeroAmount() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            100,
            address(sDaiToken),
            100,
            123
        );
        quoteData.fromTokenAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        lovToken.investWithToken(quoteData);
    }

    function test_investWithToken_fail_badToken() public {
        vm.startPrank(alice);
        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            100,
            address(sDaiToken),
            100,
            123
        );
        DummyMintableToken badToken = new DummyMintableToken(origamiMultisig, "BAD", "BAD", 18);
        deal(address(badToken), alice, 100e18);
        badToken.approve(address(lovToken), 100e18);
        quoteData.fromToken = address(badToken);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badToken)));
        lovToken.investWithToken(quoteData);
    }

    function test_investWithToken_fail_notEnough() public {
        vm.startPrank(alice);
        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            100,
            address(sDaiToken),
            100,
            123
        );
        sDaiToken.approve(address(lovToken), 100e18);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        lovToken.investWithToken(quoteData);
    }

    function test_investWithToken_success_depositToken() public {
        uint256 sDaiPrice = bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        vm.startPrank(alice);
        doMint(daiToken, alice, depositAmount);
        daiToken.approve(address(lovToken), depositAmount);

        uint256 expectedFeeBps = 20;
        uint256 expectedShares = OrigamiMath.subtractBps(
            depositAmount * 1e18 / sDaiPrice,
            expectedFeeBps,
            OrigamiMath.Rounding.ROUND_DOWN
        );

        vm.expectEmit(address(lovToken));
        emit Invested(alice, depositAmount, address(daiToken), expectedShares);
        vm.expectEmit(address(lovToken));
        emit Transfer(address(0), alice, expectedShares);
        uint256 shares = lovToken.investWithToken(quoteData);
        assertEq(shares, expectedShares);

        assertEq(lovToken.totalSupply(), shares);
        assertEq(lovToken.balanceOf(alice), shares);
        assertEq(daiToken.balanceOf(alice), 0);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);
        assertEq(sDaiToken.balanceOf(address(manager)), manager.reservesBalance());
    }

    function test_investWithToken_nothingToMint() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;

        (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
            depositAmount,
            address(daiToken),
            slippageBps,
            123
        );

        vm.startPrank(alice);
        doMint(daiToken, alice, depositAmount);
        daiToken.approve(address(lovToken), depositAmount);

        vm.mockCall(
            address(manager),
            abi.encodeWithSelector(IOrigamiOTokenManager.investWithToken.selector),
            abi.encode(0)
        );

        assertEq(
            lovToken.investWithToken(quoteData),
            0
        );
    }

    function test_investWithToken_fail_breachedMaxSupply() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = lovToken.maxInvest(address(sDaiToken)) + 2;
        assertEq(lovToken.maxInvest(address(sDaiToken)), 10_020_040.080160320641282565e18);

        // Fails if just over
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                depositAmount,
                address(sDaiToken),
                slippageBps,
                123
            );

            vm.startPrank(alice);
            doMint(sDaiToken, alice, depositAmount);
            sDaiToken.approve(address(lovToken), depositAmount);

            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.BreachedMaxTotalSupply.selector, MAX_TOTAL_SUPPLY+1, MAX_TOTAL_SUPPLY));
            lovToken.investWithToken(quoteData);
        }

        // OK with one less
        {
            (IOrigamiInvestment.InvestQuoteData memory quoteData, ) = lovToken.investQuote(
                depositAmount-1,
                address(sDaiToken),
                slippageBps,
                123
            );
            uint256 shares = lovToken.investWithToken(quoteData);
            assertEq(shares, MAX_TOTAL_SUPPLY);
            assertEq(lovToken.totalSupply(), shares);
            assertEq(lovToken.balanceOf(alice), shares);
            assertEq(sDaiToken.balanceOf(alice), 123_456e18+1);
            assertEq(sDaiToken.balanceOf(address(lovToken)), 0);
            assertEq(sDaiToken.balanceOf(address(manager)), manager.reservesBalance());
            assertEq(lovToken.maxInvest(address(sDaiToken)), 0);
        }
    }
}

contract OrigamiLovTokenTestExit is OrigamiLovTokenTestBase {
    using OrigamiMath for uint256;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Exited(address indexed user, uint256 investmentAmount, address indexed toToken, uint256 toTokenAmount, address indexed recipient);

    function test_exitToNative_failure() public {
        IOrigamiInvestment.ExitQuoteData memory quoteData;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiInvestment.Unsupported.selector));
        lovToken.exitToNative(quoteData, payable(alice));
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_maxExit() public {
        // No supply
        assertEq(lovToken.maxExit(address(daiToken)), 0);

        investWithSDai(20e18, alice);
        assertEq(lovToken.maxExit(address(daiToken)), 19.96e18);
    }

    function test_exitQuote_noDeposits() public {
        // No lovToken's minted yet -- sharesToReserves is zero so the quote comes back zero
        uint256 sharePrice1 = bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;

        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(daiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, (exitAmount * sharePrice1 / 1e18).subtractBps(MIN_EXIT_FEE_BPS, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(quoteData.minToTokenAmount, quoteData.expectedToTokenAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_DOWN));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], MIN_EXIT_FEE_BPS);
    }

    // Not testing the mock manager implementation here - just that it passes through to the manager.
    function test_exitQuote_success_depositAsset() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithSDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 50;
        uint256 expectedAmount = sDaiToken.previewRedeem(
            lovToken.sharesToReserves(
                exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
            )
        );

        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(daiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitQuote_success_reserveToken() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithSDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = lovToken.exitQuote(
            exitAmount,
            address(sDaiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 50;
        uint256 expectedAmount = lovToken.sharesToReserves(
            exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
        );
        
        assertEq(quoteData.investmentTokenAmount, exitAmount);
        assertEq(quoteData.toToken, address(sDaiToken));
        assertEq(quoteData.maxSlippageBps, slippageBps);
        assertEq(quoteData.deadline, 123);
        assertEq(quoteData.expectedToTokenAmount, expectedAmount);
        assertEq(quoteData.minToTokenAmount, expectedAmount.subtractBps(slippageBps, OrigamiMath.Rounding.ROUND_UP));
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));
        assertEq(exitFeeBps.length, 1);
        assertEq(exitFeeBps[0], expectedFeeBps);
    }

    function test_exitToToken_failZeroAmount() public {
        uint256 slippageBps = 100;
        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(sDaiToken),
            slippageBps,
            123
        );
        quoteData.investmentTokenAmount = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        lovToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_fail_zeroRecipient() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lovToken.exitToToken(quoteData, address(0));
    }

    function test_exitToToken_fail_notEnoughTokens() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        investWithDai(100e18, bob);
        investWithDai(depositAmount, alice);

        uint256 exitAmount = 100e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        vm.expectRevert("ERC20: burn amount exceeds balance");
        lovToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_fail_slippage() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 0;
        uint256 depositAmount = 20e18;
        investWithDai(depositAmount, alice);

        uint256 exitAmount = 10e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            0
        );
        quoteData.minToTokenAmount += 1;

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, quoteData.minToTokenAmount, quoteData.expectedToTokenAmount));
        lovToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_fail_badToken() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 0;
        uint256 depositAmount = 20e18;
        investWithDai(depositAmount, alice);

        uint256 exitAmount = 10e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            0
        );
        DummyMintableToken badToken = new DummyMintableToken(origamiMultisig, "BAD", "BAD", 18);
        quoteData.toToken = address(badToken);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badToken)));
        lovToken.exitToToken(quoteData, alice);
    }

    function test_exitToToken_success_depositToken() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        uint256 shares = investWithDai(depositAmount, alice);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedFeeBps = 50;
        uint256 expectedDaiAmount = sDaiToken.previewRedeem(
            lovToken.sharesToReserves(
                exitAmount.subtractBps(expectedFeeBps, OrigamiMath.Rounding.ROUND_DOWN)
            )
        );

        vm.startPrank(alice);
        vm.expectEmit(address(lovToken));
        emit Exited(alice, exitAmount, address(daiToken), expectedDaiAmount, alice);
        vm.expectEmit(address(lovToken));
        emit Transfer(alice, address(0), exitAmount);
        uint256 daiAmount = lovToken.exitToToken(quoteData, alice);
        assertEq(daiAmount, expectedDaiAmount);

        assertEq(lovToken.totalSupply(), shares - exitAmount);
        assertEq(lovToken.balanceOf(alice), shares - exitAmount);
        assertEq(daiToken.balanceOf(alice), expectedDaiAmount);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);
        assertEq(sDaiToken.balanceOf(address(manager)), manager.reservesBalance());
    }

    function test_exitToToken_success_allFees() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        uint256 shares = investWithDai(depositAmount, alice);

        vm.startPrank(origamiMultisig);
        manager.setFeeConfig(0, 10_000, 15);

        uint256 exitAmount = 15e18;
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            exitAmount,
            address(daiToken),
            slippageBps,
            123
        );

        uint256 expectedDaiAmount = 0;
        vm.startPrank(alice);
        vm.expectEmit(address(lovToken));
        emit Exited(alice, exitAmount, address(daiToken), expectedDaiAmount, alice);
        vm.expectEmit(address(lovToken));
        emit Transfer(alice, address(0), exitAmount);
        uint256 daiAmount = lovToken.exitToToken(quoteData, alice);
        assertEq(daiAmount, expectedDaiAmount);

        assertEq(lovToken.totalSupply(), shares - exitAmount);
        assertEq(lovToken.balanceOf(alice), shares - exitAmount);
        assertEq(daiToken.balanceOf(alice), expectedDaiAmount);
        assertEq(daiToken.balanceOf(address(lovToken)), 0);
        assertEq(sDaiToken.balanceOf(address(manager)), manager.reservesBalance());
    }

    function test_exitToToken_nothingToBurn() public {
        bootstrapSDai(123_456e18);
        uint256 slippageBps = 100;
        uint256 depositAmount = 20e18;
        uint256 shares = investWithDai(depositAmount, alice);

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = lovToken.exitQuote(
            shares,
            address(daiToken),
            slippageBps,
            123
        );

        // Mock that there's nothing to burn
        vm.mockCall(
            address(manager),
            abi.encodeWithSelector(IOrigamiOTokenManager.exitToToken.selector),
            abi.encode(100, 0)
        );

        vm.startPrank(alice);
        assertEq(
            lovToken.exitToToken(quoteData, alice),
            100
        );
        // The fees weren't burned
        assertEq(lovToken.totalSupply(), 19.009523809523809523e18);
    }
}

contract OrigamiLovTokenTestFees is OrigamiLovTokenTestBase {
    event PerformanceFeesCollected(address indexed feeCollector, uint256 mintAmount);
    event PerformanceFeeSet(uint256 fee);

    function test_accruedPerformanceFee() public {
        // No supply yet
        assertEq(lovToken.totalSupply(), 0);
        assertEq(lovToken.accruedPerformanceFee(), 0);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        uint256 expectedTotalSupply = 95_047.619047619047619047e18;
        assertEq(lovToken.totalSupply(), expectedTotalSupply);
        assertEq(lovToken.accruedPerformanceFee(), 0);

        vm.warp(block.timestamp + 182.5 days);
        assertEq(lovToken.accruedPerformanceFee(), expectedTotalSupply * 500 / 10_000 / 2);

        vm.warp(block.timestamp + 182.5 days);
        assertEq(lovToken.accruedPerformanceFee(), expectedTotalSupply * 500 / 10_000);
    }

    function test_collectPerformanceFees_success() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        uint256 totalSupply = lovToken.totalSupply();

        vm.startPrank(origamiMultisig);
        lovToken.collectPerformanceFees();
        assertEq(lovToken.balanceOf(feeCollector), 0);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);

        vm.warp(block.timestamp + 182.5 days);
        uint256 expectedAmount = totalSupply * 500 / 10_000 / 2;
        vm.expectEmit(address(lovToken));
        emit PerformanceFeesCollected(feeCollector, expectedAmount);
        uint256 amount = lovToken.collectPerformanceFees();
        assertEq(amount, expectedAmount);
        assertEq(lovToken.balanceOf(feeCollector), expectedAmount);
        assertEq(lovToken.totalSupply(), totalSupply + expectedAmount);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);

        uint256 expectedAmount2 = (totalSupply + expectedAmount) * 500 / 10_000 / 2;
        vm.warp(block.timestamp + 182.5 days);
        vm.expectEmit(address(lovToken));
        emit PerformanceFeesCollected(feeCollector, expectedAmount2);
        amount = lovToken.collectPerformanceFees();
        assertEq(amount, expectedAmount2);
        assertEq(lovToken.balanceOf(feeCollector), expectedAmount + expectedAmount2);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);
    }

    function test_setAnnualPerformanceFee_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        lovToken.setAnnualPerformanceFee(10_001);
    }

    function test_setAnnualPerformanceFee_successNoSupply() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit PerformanceFeeSet(123);
        lovToken.setAnnualPerformanceFee(123);
        assertEq(lovToken.annualPerformanceFeeBps(), 123);
        assertEq(lovToken.balanceOf(feeCollector), 0);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);
    }

    function test_setAnnualPerformanceFee_successWithSupply() public {
        vm.warp(1702020398);
        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);
        uint256 totalSupply = lovToken.totalSupply();

        vm.warp(block.timestamp + 365 days);
        uint256 expectedAmount = totalSupply * 500 / 10_000;

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lovToken));
        emit PerformanceFeesCollected(feeCollector, expectedAmount);
        vm.expectEmit(address(lovToken));
        emit PerformanceFeeSet(123);
        lovToken.setAnnualPerformanceFee(123);
        assertEq(lovToken.annualPerformanceFeeBps(), 123);
        assertEq(lovToken.balanceOf(feeCollector), 4_752.380952380952380952e18);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);
    }
    
    function test_collectPerformanceFees_nothingToMint() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = 100_000e18;
        investWithDai(depositAmount, alice);

        uint256 totalSupply = lovToken.totalSupply();
        assertEq(totalSupply, 95_047.619047619047619047e18);

        vm.startPrank(origamiMultisig);
        lovToken.setAnnualPerformanceFee(0);

        uint256 amount = lovToken.collectPerformanceFees();
        assertEq(amount, 0);
        assertEq(lovToken.balanceOf(feeCollector), 0);
    }

    function test_collectPerformanceFees_overMaxTotalSupply() public {
        vm.warp(1702020398);

        bootstrapSDai(123_456e18);
        uint256 depositAmount = lovToken.maxInvest(address(daiToken));
        investWithDai(depositAmount, alice);

        uint256 totalSupply = lovToken.totalSupply();

        vm.startPrank(origamiMultisig);
        lovToken.collectPerformanceFees();
        assertEq(lovToken.balanceOf(feeCollector), 0);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);

        vm.warp(block.timestamp + 182.5 days);
        uint256 expectedAmount = totalSupply * 500 / 10_000 / 2;
        vm.expectEmit(address(lovToken));
        emit PerformanceFeesCollected(feeCollector, expectedAmount);
        uint256 amount = lovToken.collectPerformanceFees();
        assertEq(amount, expectedAmount);
        assertEq(lovToken.balanceOf(feeCollector), expectedAmount);
        assertEq(lovToken.totalSupply(), totalSupply + expectedAmount);
        assertEq(totalSupply + expectedAmount, 10_249_999.999999999999999998e18);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);

        uint256 expectedAmount2 = (totalSupply + expectedAmount) * 500 / 10_000 / 2;
        vm.warp(block.timestamp + 182.5 days);
        vm.expectEmit(address(lovToken));
        emit PerformanceFeesCollected(feeCollector, expectedAmount2);
        amount = lovToken.collectPerformanceFees();
        assertEq(amount, expectedAmount2);
        assertEq(lovToken.balanceOf(feeCollector), expectedAmount + expectedAmount2);
        assertEq(lovToken.lastPerformanceFeeTime(), block.timestamp);
    }
}