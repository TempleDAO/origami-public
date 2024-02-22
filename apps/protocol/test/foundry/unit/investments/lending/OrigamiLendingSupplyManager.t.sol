pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiLendingSupplyManager } from "contracts/investments/lending/OrigamiLendingSupplyManager.sol";
import { OrigamiCircuitBreakerProxy } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerProxy.sol";
import { OrigamiCircuitBreakerAllUsersPerPeriod } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyLendingClerk } from "test/foundry/mocks/investments/lending/DummyLendingClerk.m.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiInvestment } from "contracts/interfaces/investments/IOrigamiInvestment.sol";
import { OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";

contract OrigamiLendingSupplyManagerTestBase is OrigamiTest {

    DummyMintableToken public usdcToken;
    DummyMintableToken public oUsdc;
    DummyMintableToken public ovUsdc;
    OrigamiCircuitBreakerProxy public cbProxy;
    OrigamiCircuitBreakerAllUsersPerPeriod public cbOUsdcExit;
    OrigamiLendingSupplyManager public supplyManager;

    DummyLendingClerk public lendingClerk;

    bytes32 public constant EXIT = keccak256("EXIT");

    function setUp() public {
        usdcToken = new DummyMintableToken(origamiMultisig, "USDC", "USDC", 6);
        oUsdc = new DummyMintableToken(origamiMultisig, "oUSDC", "oUSDC", 18);
        ovUsdc = new DummyMintableToken(origamiMultisig, "ovUSDC", "ovUSDC", 18);
        cbProxy = new OrigamiCircuitBreakerProxy(origamiMultisig);
        cbOUsdcExit = new OrigamiCircuitBreakerAllUsersPerPeriod(origamiMultisig, address(cbProxy), 26 hours, 13, 2_000_000e18);

        supplyManager = new OrigamiLendingSupplyManager(
            origamiMultisig, 
            address(usdcToken), 
            address(oUsdc),
            address(ovUsdc),
            address(cbProxy)
        );

        vm.startPrank(origamiMultisig);
        cbProxy.setIdentifierForCaller(address(supplyManager), "EXIT");
        cbProxy.setCircuitBreaker(EXIT, address(oUsdc), address(cbOUsdcExit));

        OrigamiDebtToken iUsdc = new OrigamiDebtToken("Origami iUSDC", "iUSDC", origamiMultisig);
        lendingClerk = new DummyLendingClerk(address(usdcToken), address(iUsdc));
        supplyManager.setLendingClerk(address(lendingClerk));
        vm.stopPrank();
    }
}

contract OrigamiLendingSupplyManagerTestAdmin is OrigamiLendingSupplyManagerTestBase {
    event LendingClerkSet(address indexed lendingClerk);

    function test_initialization() public {
        assertEq(supplyManager.owner(), origamiMultisig);
        assertEq(address(supplyManager.asset()), address(usdcToken));
        assertEq(supplyManager.baseToken(), address(usdcToken));
        assertEq(address(supplyManager.oToken()), address(oUsdc));
        assertEq(address(supplyManager.ovToken()), address(ovUsdc));
        assertEq(address(supplyManager.circuitBreakerProxy()), address(cbProxy));
        assertEq(supplyManager.areInvestmentsPaused(), false);
        assertEq(supplyManager.areExitsPaused(), false);

        address[] memory tokens = supplyManager.acceptedInvestTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(usdcToken));

        tokens = supplyManager.acceptedExitTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(usdcToken));
    }

    function test_setLendingClerk_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        supplyManager.setLendingClerk(address(0));
    }

    function test_setLendingClerk_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(supplyManager));
        emit LendingClerkSet(address(lendingClerk));
        supplyManager.setLendingClerk(address(lendingClerk));
        assertEq(address(supplyManager.lendingClerk()), address(lendingClerk));
        assertEq(usdcToken.allowance(address(supplyManager), address(lendingClerk)), type(uint256).max);

        vm.expectEmit(address(supplyManager));
        emit LendingClerkSet(bob);
        supplyManager.setLendingClerk(bob);
        assertEq(address(supplyManager.lendingClerk()), bob);
        assertEq(usdcToken.allowance(address(supplyManager), address(lendingClerk)), 0);
        assertEq(usdcToken.allowance(address(supplyManager), bob), type(uint256).max);
    }

    function test_recoverToken() public {
        check_recoverToken(address(supplyManager));
    }

    function test_areInvestmentsPaused() public {
        assertEq(supplyManager.areInvestmentsPaused(), false);

        vm.startPrank(origamiMultisig);
        supplyManager.setPauser(origamiMultisig, true);
        supplyManager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        assertEq(supplyManager.areInvestmentsPaused(), true);
    }

    function test_areExitsPaused() public {
        assertEq(supplyManager.areExitsPaused(), false);

        vm.startPrank(origamiMultisig);
        supplyManager.setPauser(origamiMultisig, true);
        supplyManager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        assertEq(supplyManager.areExitsPaused(), true);
    }
}

contract OrigamiLendingSupplyManagerTestAccess is OrigamiLendingSupplyManagerTestBase {
    function test_access_setLendingClerk() public {
        expectElevatedAccess();
        supplyManager.setLendingClerk(alice);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        supplyManager.recoverToken(alice, alice, 100e18);
    }

    function test_access_investWithToken() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            100e6,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        supplyManager.investWithToken(alice, quoteData);
    }

    function test_access_exitToToken() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData,) = supplyManager.exitQuote(
            100e6,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        supplyManager.exitToToken(alice, quoteData, alice);
    }
}

contract OrigamiLendingSupplyManagerTestInvestExit is OrigamiLendingSupplyManagerTestBase {
    function test_maxInvest() public {
        assertEq(supplyManager.maxInvest(bob), 0);
        assertEq(supplyManager.maxInvest(address(usdcToken)), type(uint256).max);
    }

    function test_maxExit() public {
        // Fake that the lending clerk has USDC available for borrow/exit
        deal(address(usdcToken), address(lendingClerk), 100e6, true);

        assertEq(supplyManager.maxExit(bob), 0);
        assertEq(supplyManager.maxExit(address(usdcToken)), 100e18);
    }

    function test_investQuote_success() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData, uint256[] memory investFeeBps) = supplyManager.investQuote(
            100e6,
            address(usdcToken),
            123,
            100
        );

        assertEq(quoteData.fromToken, address(usdcToken));
        assertEq(quoteData.fromTokenAmount, 100e6);
        assertEq(quoteData.maxSlippageBps, 123);
        assertEq(quoteData.deadline, 100);
        assertEq(quoteData.expectedInvestmentAmount, 100e18);
        assertEq(quoteData.minInvestmentAmount, 100e18);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(investFeeBps.length, 0);
    }

    function test_investQuote_fail() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, bob));
        supplyManager.investQuote(
            100e6,
            bob,
            0,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        supplyManager.investQuote(
            0,
            address(usdcToken),
            0,
            0
        );
    }

    function test_exitQuote_success() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, uint256[] memory exitFeeBps) = supplyManager.exitQuote(
            100e18,
            address(usdcToken),
            123,
            100
        );

        assertEq(quoteData.investmentTokenAmount, 100e18);
        assertEq(quoteData.toToken, address(usdcToken));
        assertEq(quoteData.maxSlippageBps, 123);
        assertEq(quoteData.deadline, 100);
        assertEq(quoteData.expectedToTokenAmount, 100e6);
        assertEq(quoteData.minToTokenAmount, 100e6);
        assertEq(quoteData.underlyingInvestmentQuoteData, bytes(""));

        assertEq(exitFeeBps.length, 0);
    }

    function test_investWithToken_fail_paused() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            100e6,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(origamiMultisig);
        supplyManager.setPauser(origamiMultisig, true);
        supplyManager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        vm.startPrank(address(oUsdc));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        supplyManager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_fail_token() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            100e6,
            address(usdcToken),
            0,
            0
        );

        quoteData.fromToken = bob;
        vm.startPrank(address(oUsdc));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, bob));
        supplyManager.investWithToken(alice, quoteData);
    }

    function test_investWithToken_fail_contract() public {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            100e6,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(address(oUsdc));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        supplyManager.investWithToken(address(lendingClerk), quoteData);
    }

    function test_investWithToken_success_eoa() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            amountIn,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(address(oUsdc));
        deal(address(usdcToken), address(supplyManager), amountIn);
        uint256 investmentAmount = supplyManager.investWithToken(alice, quoteData);
        assertEq(investmentAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), amountIn);
        assertEq(lendingClerk.totalAvailableToWithdraw(), amountIn);
    }

    function test_investWithToken_success_ovToken() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            amountIn,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(address(oUsdc));
        deal(address(usdcToken), address(supplyManager), amountIn);
        uint256 investmentAmount = supplyManager.investWithToken(address(ovUsdc), quoteData);
        assertEq(investmentAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), amountIn);
        assertEq(lendingClerk.totalAvailableToWithdraw(), amountIn);
    }

    function test_investWithToken_success_contract() public {
        // Give the lendingClerk access (faking a 3rd party protocol)
        vm.startPrank(origamiMultisig);
        supplyManager.setAllowAccount(address(lendingClerk), true);

        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            amountIn,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(address(oUsdc));
        deal(address(usdcToken), address(supplyManager), amountIn);
        uint256 investmentAmount = supplyManager.investWithToken(address(lendingClerk), quoteData);
        assertEq(investmentAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), amountIn);
        assertEq(lendingClerk.totalAvailableToWithdraw(), amountIn);
    }

    function test_exitToToken_fail_paused() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            100e18,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(origamiMultisig);
        supplyManager.setPauser(origamiMultisig, true);
        supplyManager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        vm.startPrank(address(oUsdc));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        supplyManager.exitToToken(alice, quoteData, alice);
    }

    function test_exitToToken_fail_zeroRecipient() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        _invest(alice, amountIn);

        vm.startPrank(address(oUsdc));

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            amountOut,
            address(usdcToken),
            0,
            0
        );

        vm.expectRevert("ERC20: transfer to the zero address");
        supplyManager.exitToToken(alice, quoteData, address(0));
    }

    function test_exitToToken_fail_token() public {
        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            100e18,
            address(usdcToken),
            0,
            0
        );

        quoteData.toToken = bob;
        vm.startPrank(address(oUsdc));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, bob));
        supplyManager.exitToToken(alice, quoteData, alice);
    }

    function _invest(address account, uint256 amount) internal returns (uint256) {
        (IOrigamiInvestment.InvestQuoteData memory quoteData,) = supplyManager.investQuote(
            amount,
            address(usdcToken),
            0,
            0
        );

        vm.startPrank(address(oUsdc));
        deal(address(usdcToken), address(supplyManager), amount);
        return supplyManager.investWithToken(account, quoteData);
    }

    function test_exitToToken_fail_circuitBreaker() public {
        uint256 amount = 2_000_000e18;
        _invest(alice, 4_000_000e6);

        vm.startPrank(address(oUsdc));

        // max out the circuit breaker
        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
                amount,
                address(usdcToken),
                0,
                0
            );

            supplyManager.exitToToken(alice, quoteData, alice);
        }

        // trying for 1 more wei fails
        {
            (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
                1,
                address(usdcToken),
                0,
                0
            );

            vm.expectRevert(abi.encodeWithSelector(OrigamiCircuitBreakerAllUsersPerPeriod.CapBreached.selector, amount+1, amount));
            supplyManager.exitToToken(alice, quoteData, alice); 
        }
    }

    function test_exitToToken_success_eoa() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        _invest(alice, amountIn);

        vm.startPrank(address(oUsdc));

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            amountOut,
            address(usdcToken),
            0,
            0
        );

        (uint256 toTokenAmount, uint256 toBurnAmount) = supplyManager.exitToToken(alice, quoteData, bob);
        assertEq(toTokenAmount, amountIn);
        assertEq(toBurnAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(bob), amountIn);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
    }

    function test_exitToToken_success_contract() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 100e18;
        _invest(alice, amountIn);

        vm.startPrank(address(oUsdc));

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            amountOut,
            address(usdcToken),
            0,
            0
        );

        // Don't need to whitelist the `account` param when exiting
        (uint256 toTokenAmount, uint256 toBurnAmount) = supplyManager.exitToToken(address(lendingClerk), quoteData, bob);
        assertEq(toTokenAmount, amountIn);
        assertEq(toBurnAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(bob), amountIn);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
    }

    function test_exitToToken_success_smallAmount() public {
        uint256 amountIn = 100e6;
        uint256 amountOut = 12345;
        _invest(alice, amountIn);

        vm.startPrank(address(oUsdc));

        (IOrigamiInvestment.ExitQuoteData memory quoteData, ) = supplyManager.exitQuote(
            amountOut,
            address(usdcToken),
            0,
            0
        );

        (uint256 toTokenAmount, uint256 toBurnAmount) = supplyManager.exitToToken(alice, quoteData, bob);
        assertEq(toTokenAmount, 0);
        assertEq(toBurnAmount, amountOut);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), amountIn);
        assertEq(usdcToken.balanceOf(bob), 0);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(lendingClerk.totalAvailableToWithdraw(), amountIn);
    }

}
