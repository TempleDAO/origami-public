pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiDebtTokenTestBase } from "./OrigamiDebtTokenTestBase.t.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */

contract OrigamiDebtTokenTest is OrigamiDebtTokenTestBase {

    uint96 public aliceInterestRate = 0.02e18;
    uint96 public bobInterestRate = 0.05e18;

    function setUp() public {
        _setUp();

        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, aliceInterestRate);
        iUSDC.setInterestRate(bob, bobInterestRate);
        vm.stopPrank();
    }

    function test_mint_fail_invalidParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.mint(address(0), 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        iUSDC.mint(alice, 0);
    }

    function test_mint_alice_success() public {
        vm.prank(origamiMultisig);
        uint256 amount = 100e18;

        vm.expectEmit(address(iUSDC));
        emit Transfer(address(0), alice, amount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, uint128(amount), 0);
        iUSDC.mint(alice, amount);

        // Just the principal at the same block
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, block.timestamp, amount);

        vm.warp(block.timestamp + 365 days);
        checkpointInterest(alice);

        uint256 expectedTotal = TWO_PCT_365DAY;
        uint256 expectedInterestOnly = expectedTotal - amount;
        checkTotals(amount, expectedInterestOnly, 0);
        checkDebtor(alice, aliceInterestRate, amount, expectedInterestOnly, block.timestamp, expectedTotal);
    }

    function test_mint_aliceAndBob_inSameBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        iUSDC.mint(bob, amount);

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, block.timestamp, amount);
        checkDebtor(bob, bobInterestRate, amount, 0, block.timestamp, amount);

        vm.warp(block.timestamp + 365 days);
        checkpointInterest(alice, bob);

        uint256 aliceExpectedTotal = TWO_PCT_365DAY;
        uint256 aliceExpectedInterestOnly = aliceExpectedTotal - amount;

        uint256 bobExpectedTotal = FIVE_PCT_365DAY;
        uint256 bobExpectedInterestOnly = bobExpectedTotal - amount;

        checkTotals(2*amount, aliceExpectedInterestOnly+bobExpectedInterestOnly, 0);
        checkDebtor(alice, aliceInterestRate, amount, aliceExpectedInterestOnly, block.timestamp, aliceExpectedTotal);
        checkDebtor(bob, bobInterestRate, amount, bobExpectedInterestOnly, block.timestamp, bobExpectedTotal);
    }

    function test_mint_aliceAndBob_inDifferentBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);

        // Bob borrows 1 day later
        uint256 blockTs = block.timestamp;
        vm.warp(blockTs + 1 days);
        iUSDC.mint(bob, amount);

        uint256 aliceExpectedDebt = TWO_PCT_1DAY;
        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, aliceExpectedDebt);
        checkDebtor(bob, bobInterestRate, amount, 0, block.timestamp, amount);

        vm.warp(block.timestamp + 364 days);
        checkpointInterest(alice, bob);

        aliceExpectedDebt = TWO_PCT_365DAY;
        uint256 bobExpectedDebt = FIVE_PCT_364DAY;
        checkTotals(2*amount, aliceExpectedDebt + bobExpectedDebt - 2*amount, 0);
        checkDebtor(alice, aliceInterestRate, amount, aliceExpectedDebt-amount, block.timestamp, aliceExpectedDebt);
        checkDebtor(bob, bobInterestRate, amount, bobExpectedDebt-amount, block.timestamp, bobExpectedDebt);
    }

    function test_burn_fail_invalidParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.burn(address(0), 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        iUSDC.burn(alice, 0);
    }

    function test_burn_everything_alice_inSameBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);

        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, 0, 0);
        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, address(0), amount);
        iUSDC.burn(alice, amount);

        checkTotals(0, 0, 0);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_everything_alice_aDayLater() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        uint256 expectedBal = TWO_PCT_1DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);

        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, 0, 0);
        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, address(0), expectedBal);
        iUSDC.burn(alice, expectedBal);

        checkTotals(0, 0, expectedBal-amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_partial_alice_aDayLater() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        uint256 expectedBal = TWO_PCT_1DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);

        uint256 expectedPrincipalRemaining = expectedBal-amount;

        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, uint128(expectedPrincipalRemaining), 0);
        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, address(0), amount);
        iUSDC.burn(alice, amount);

        checkTotals(expectedPrincipalRemaining, 0, expectedBal-amount);
        checkDebtor(alice, aliceInterestRate, expectedPrincipalRemaining, 0, block.timestamp, expectedPrincipalRemaining);
    }

    function test_burn_everything_aliceAndBob_inSameBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        iUSDC.mint(bob, amount);
        iUSDC.burn(alice, amount);
        iUSDC.burn(bob, amount);

        checkTotals(0, 0, 0);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_everything_aliceAndBob_aDayLater() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        iUSDC.mint(bob, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        uint256 expectedAliceBal = TWO_PCT_1DAY;
        uint256 expectedBobBal = FIVE_PCT_1DAY;

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedAliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs, expectedBobBal);

        iUSDC.burn(alice, expectedAliceBal);
        iUSDC.burn(bob, expectedBobBal);

        checkTotals(0, 0, expectedAliceBal+expectedBobBal-2*amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_aliceAndBob_inDifferentBlocks() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs1 = block.timestamp;
        vm.warp(block.timestamp + 1 days);
        uint256 blockTs2 = block.timestamp;
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 1 days);

        uint256 expectedAliceBal = TWO_PCT_2DAY;
        uint256 expectedBobBal = FIVE_PCT_1DAY;
        
        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs1, expectedAliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs2, expectedBobBal);
        
        // Alice pays it off fully
        iUSDC.burn(alice, expectedAliceBal);

        checkTotals(amount, 0, expectedAliceBal-amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs2, expectedBobBal);

        // Bob pays it off fully
        iUSDC.burn(bob, expectedBobBal);

        checkTotals(0, 0, expectedAliceBal+expectedBobBal-2*amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_alice_interestRepayOnly() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        uint256 expectedBal = TWO_PCT_365DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);

        uint256 repayAmount = 1e18;
        iUSDC.burn(alice, repayAmount);

        // Expected remaining debtor interest = prior balance minus the repayment amount
        uint256 expectedBal2 = expectedBal - repayAmount;
        checkTotals(amount, expectedBal2-amount, repayAmount);
        checkDebtor(alice, aliceInterestRate, amount, expectedBal2-amount, block.timestamp, expectedBal2);
    }

    function test_burn_aliceAndBob_partial() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs1 = block.timestamp;
        vm.warp(block.timestamp + 1 days);
        uint256 blockTs2 = block.timestamp;
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 1 days);

        uint256 expectedAliceBal = TWO_PCT_2DAY;
        uint256 expectedBobBal = FIVE_PCT_1DAY;

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs1, expectedAliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs2, expectedBobBal);
        
        // Alice pays 10e18 off
        uint256 repayAmount = 10e18;
        iUSDC.burn(alice, repayAmount);

        uint256 expectedAliceBal2 = expectedAliceBal-repayAmount;

        // bob hasn't had a checkpoint so the estimate debtor interest is zero)
        checkTotals(expectedAliceBal2 + amount, 0, expectedAliceBal-amount);
        checkDebtor(alice, aliceInterestRate, expectedAliceBal2, 0, block.timestamp, expectedAliceBal2);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs2, expectedBobBal);

        // Alice pays the remainder off
        iUSDC.burn(alice, expectedAliceBal2);

        checkTotals(amount, 0, expectedAliceBal-amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, amount, 0, blockTs2, expectedBobBal);
    }

    function test_setInterestRate_fail_tooHigh() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        iUSDC.setInterestRate(alice, 10e18 + 1);
    }

    function test_setInterestRate() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        uint256 startBlockTs = block.timestamp;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);

        uint256 aliceBal = TWO_PCT_365DAY;
        uint256 bobBal = FIVE_PCT_364DAY;

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, startBlockTs, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        vm.startPrank(origamiMultisig);
        uint96 updatedRate = 0.1e18;
        iUSDC.setInterestRate(alice, updatedRate);

        // The rate was updated and a checkpoint was made.
        // bob's extra interest isn't added to the estimatedDebtorInterest because he didn't checkpoint
        checkTotals(2*amount, aliceBal-amount, 0);
        checkDebtor(alice, updatedRate, amount, aliceBal-amount, block.timestamp, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        uint256 ts = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        // 365 days of 10% interest on ONE_PCT_365DAY_ROUNDING
        uint256 aliceBal2 = TEN_PCT_365DAY_1;
        
        bobBal = FIVE_PCT_729DAY;
        checkTotals(2*amount, aliceBal-amount, 0);
        checkDebtor(alice, updatedRate, amount, aliceBal-amount, ts, aliceBal2);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);
    }
    
    function test_setInterestRateToZero() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        uint256 startBlockTs = block.timestamp;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);

        uint256 aliceBal = TWO_PCT_365DAY;
        uint256 bobBal = FIVE_PCT_364DAY;

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, startBlockTs, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        vm.startPrank(origamiMultisig);
        uint96 updatedRate = 0;
        iUSDC.setInterestRate(alice, updatedRate);

        // The rate was updated and a checkpoint was made.
        // bob's extra interest isn't added to the estimatedDebtorInterest because he didn't checkpoint
        checkTotals(2*amount, aliceBal-amount, 0);
        checkDebtor(alice, updatedRate, amount, aliceBal-amount, block.timestamp, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        uint256 ts = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        // 365 days of 0% interest. So Alice's balance remains the same.
        uint256 aliceBal2 = aliceBal;
        
        bobBal = FIVE_PCT_729DAY;
        checkTotals(2*amount, aliceBal-amount, 0);
        checkDebtor(alice, updatedRate, amount, aliceBal-amount, ts, aliceBal2);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);
    }

    function test_burnAll_fail_invalidParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.burnAll(address(0));

        uint256 burnedAmount = iUSDC.burnAll(alice);
        assertEq(burnedAmount, 0);
    }

    function test_burnAll() public {
        vm.startPrank(origamiMultisig);

        uint256 amount = 100e18;
        uint256 startBlockTs = block.timestamp;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);
        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0.1e18);
        vm.warp(block.timestamp + 365 days);

        uint256 bobBal = FIVE_PCT_729DAY;

        vm.startPrank(origamiMultisig);
        iUSDC.burnAll(alice);
        checkTotals(amount, 0, TEN_PCT_365DAY_1-amount);
        checkDebtor(alice, 0.1e18, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        iUSDC.burnAll(bob);
        checkTotals(0, 0, TEN_PCT_365DAY_1+FIVE_PCT_729DAY-2*amount);
        checkDebtor(alice, 0.1e18, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, 0, 0, block.timestamp, 0);
    }

    function test_burn_fail_tooMuch() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        uint256 expectedBal = TWO_PCT_365DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        // Burning too much reverts
        uint256 burnAmount = expectedBal+1;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUSDC), burnAmount, expectedBal));
        iUSDC.burn(alice, burnAmount);
    }

    function test_transfer_fail_invalidParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.transfer(address(0), 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        iUSDC.transfer(alice, 0);
    }

    function test_transferFrom_fail_invalidParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.transferFrom(address(0), alice, 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.transferFrom(bob, address(0), 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        iUSDC.transferFrom(bob, alice, 0);
    }

    function test_transfer_fail_tooMuch() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUSDC), amount, 0));
        iUSDC.transfer(bob, amount);
    }

    function test_transfer_everything_inSameBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(origamiMultisig, amount);

        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(origamiMultisig, 0, amount, 0, block.timestamp, amount);
        checkDebtor(bob, bobInterestRate, 0, 0, block.timestamp, 0);

        vm.expectEmit(address(iUSDC));
        emit Transfer(origamiMultisig, bob, amount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(origamiMultisig, 0, 0);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(amount), 0);
        iUSDC.transfer(bob, amount);

        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(origamiMultisig, 0, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, amount, 0, block.timestamp, amount);
    }

    function test_transferFrom_everything_inSameBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);

        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, bob, amount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, 0, 0);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(amount), 0);
        iUSDC.transferFrom(alice, bob, amount);

        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, amount, 0, block.timestamp, amount);
    }

    function test_transferFrom_everything_aDayLater() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        uint256 expectedBal = TWO_PCT_1DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, bob, expectedBal);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, 0, 0);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(expectedBal), 0);
        iUSDC.transferFrom(alice, bob, expectedBal);

        checkTotals(expectedBal, 0, expectedBal-amount);
        checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
        checkDebtor(bob, bobInterestRate, expectedBal, 0, block.timestamp, expectedBal);
    }

    function test_transferFrom_partial_aDayLater() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 1 days);

        uint256 expectedBal = TWO_PCT_1DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        uint256 expectedPrincipalRemaining = expectedBal-amount;

        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, bob, amount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, uint128(expectedPrincipalRemaining), 0);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(amount), 0);
        iUSDC.transferFrom(alice, bob, amount);

        checkTotals(expectedBal, 0, expectedBal-amount);
        checkDebtor(alice, aliceInterestRate, expectedPrincipalRemaining, 0, block.timestamp, expectedPrincipalRemaining);
        checkDebtor(bob, bobInterestRate, amount, 0, block.timestamp, amount);
    }

    function test_transferFrom_interestRepayOnly() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        uint256 expectedBal = TWO_PCT_365DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        uint256 transferAmount = 1e18;
        uint256 remainingAmount = expectedBal - transferAmount;

        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, bob, transferAmount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, uint128(amount), uint128(remainingAmount-amount));
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(transferAmount), 0);
        assertEq(iUSDC.transferFrom(alice, bob, transferAmount), true);

        checkTotals(amount+transferAmount, expectedBal-amount-transferAmount, transferAmount);
        checkDebtor(alice, aliceInterestRate, amount, remainingAmount-amount, block.timestamp, remainingAmount);
        checkDebtor(bob, bobInterestRate, transferAmount, 0, block.timestamp, transferAmount);
    }

    function test_transferFrom_interestAndSomePrincipal() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        uint256 expectedBal = TWO_PCT_365DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        uint256 transferAmount = 10e18;
        uint256 remainingAmount = expectedBal - transferAmount;

        vm.expectEmit(address(iUSDC));
        emit Transfer(alice, bob, transferAmount);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(alice, uint128(remainingAmount), 0);
        vm.expectEmit(address(iUSDC));
        emit DebtorBalance(bob, uint128(transferAmount), 0);
        assertEq(iUSDC.transferFrom(alice, bob, transferAmount), true);

        checkTotals(expectedBal, 0, expectedBal-amount);
        checkDebtor(alice, aliceInterestRate, remainingAmount, 0, block.timestamp, remainingAmount);
        checkDebtor(bob, bobInterestRate, transferAmount, 0, block.timestamp, transferAmount);
    }

    function test_transferFrom_fails_tooMuch() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        uint256 blockTs = block.timestamp;
        vm.warp(block.timestamp + 365 days);

        uint256 expectedBal = TWO_PCT_365DAY;
        checkTotals(amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, blockTs, expectedBal);
        checkDebtor(bob, bobInterestRate, 0, 0, 1, 0);

        uint256 transferAmount = expectedBal+1;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUSDC), transferAmount, expectedBal));
        iUSDC.transferFrom(alice, bob, transferAmount);

        // Ok with the exact balance
        {
            vm.expectEmit(address(iUSDC));
            emit Transfer(alice, bob, expectedBal);
            vm.expectEmit(address(iUSDC));
            emit DebtorBalance(alice, 0, 0);
            vm.expectEmit(address(iUSDC));
            emit DebtorBalance(bob, uint128(expectedBal), 0);
            assertEq(iUSDC.transferFrom(alice, bob, expectedBal), true);

            checkTotals(expectedBal, 0, expectedBal-amount);
            checkDebtor(alice, aliceInterestRate, 0, 0, block.timestamp, 0);
            checkDebtor(bob, bobInterestRate, expectedBal, 0, block.timestamp, expectedBal);
        }
    }

    function test_checkpointDebtorsInterest_fail() public {
        address[] memory addrs = new address[](2);
        (addrs[0], addrs[1]) = (alice, address(0));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        iUSDC.checkpointDebtorsInterest(addrs);       
    }

    function test_checkpointDebtorsInterest_success() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        uint256 startBlockTs = block.timestamp;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);
        vm.warp(block.timestamp + 364 days);

        uint256 aliceBal = TWO_PCT_365DAY;
        uint256 bobBal = FIVE_PCT_364DAY;

        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, aliceInterestRate, amount, 0, startBlockTs, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, 0, startBlockTs + 1 days, bobBal);

        checkpointInterest(alice, bob);
        checkTotals(2*amount, (aliceBal+bobBal)-2*amount, 0);
        checkDebtor(alice, aliceInterestRate, amount, aliceBal-amount, block.timestamp, aliceBal);
        checkDebtor(bob, bobInterestRate, amount, bobBal-amount, block.timestamp, bobBal);

        uint256 repayAmount = 50e18;
        iUSDC.burn(alice, repayAmount);
        uint256 interestAliceRepaid = aliceBal-amount;
        checkTotals(amount + interestAliceRepaid + repayAmount, bobBal-amount, aliceBal-amount);
        checkDebtor(alice, aliceInterestRate, interestAliceRepaid + repayAmount, 0, block.timestamp, aliceBal-repayAmount);
        checkDebtor(bob, bobInterestRate, amount, bobBal-amount, block.timestamp, bobBal);
    }

    function test_currentDebtOf() public {
        vm.startPrank(origamiMultisig);

        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);
        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0.1e18);
        vm.warp(block.timestamp + 365 days);

        (IOrigamiDebtToken.DebtOwed memory aliceDebt, IOrigamiDebtToken.DebtOwed memory bobDebt) = currentDebtsOf(alice, bob);
        assertEq(aliceDebt.principal, amount);
        assertEq(aliceDebt.interest, TEN_PCT_365DAY_1-amount);
        assertEq(iUSDC.balanceOf(alice), aliceDebt.principal + aliceDebt.interest);

        assertEq(bobDebt.principal, amount);
        assertEq(bobDebt.interest, FIVE_PCT_729DAY-amount);
        assertEq(iUSDC.balanceOf(bob), bobDebt.principal+bobDebt.interest);
    }

    function test_getDebtorPosition() public {
        vm.startPrank(origamiMultisig);

        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);

        IOrigamiDebtToken.DebtorPosition memory cache = iUSDC.getDebtorPosition(alice);
        assertEq(cache.principal, amount);
        assertEq(cache.interest, TWO_PCT_365DAY - amount);
        assertEq(cache.interestDelta, TWO_PCT_365DAY - amount);
        assertEq(cache.rate, aliceInterestRate);

        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0.1e18);
        vm.warp(block.timestamp + 365 days);

        cache = iUSDC.getDebtorPosition(alice);
        assertEq(cache.principal, amount);
        assertEq(cache.interest, TEN_PCT_365DAY_1 - amount);
        assertEq(cache.interestDelta, TEN_PCT_365DAY_1 - TWO_PCT_365DAY);
        assertEq(cache.rate, 0.1e18);

        cache = iUSDC.getDebtorPosition(bob);
        assertEq(cache.principal, amount);
        assertEq(cache.interest, FIVE_PCT_729DAY-amount);
        assertEq(cache.interestDelta, FIVE_PCT_729DAY-amount);
        assertEq(cache.rate, bobInterestRate);
    }

    function mkList(address addr) private pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = addr;
    }

    function mkList(address addr1, address addr2) private pure returns (address[] memory list) {
        list = new address[](2);
        list[0] = addr1;
        list[1] = addr2;
    }

    function test_totalSupplyExcluding() public {
        vm.startPrank(origamiMultisig);

        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);

        IOrigamiDebtToken.DebtorPosition memory cache = iUSDC.getDebtorPosition(alice);
        assertEq(cache.principal, amount);
        assertEq(cache.interest, TWO_PCT_365DAY - amount);
        assertEq(cache.interestDelta, TWO_PCT_365DAY - amount);
        assertEq(cache.rate, aliceInterestRate);

        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0.1e18);
        vm.warp(block.timestamp + 365 days);

        // Only includes checkpoint data
        assertEq(iUSDC.totalSupplyExcluding(mkList(alice)), amount);
        assertEq(iUSDC.totalSupplyExcluding(mkList(bob)), TWO_PCT_365DAY);
        assertEq(iUSDC.totalSupply(), TWO_PCT_365DAY+amount);

        // Do a checkpoint and re-check
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (alice, bob);
        vm.expectEmit(address(iUSDC));
        emit Checkpoint(alice, uint128(amount), uint128(TEN_PCT_365DAY_1-amount));
        vm.expectEmit(address(iUSDC));
        emit Checkpoint(bob, uint128(amount), uint128(FIVE_PCT_729DAY-amount));
        iUSDC.checkpointDebtorsInterest(_debtors);

        assertEq(iUSDC.totalSupplyExcluding(mkList(alice)), FIVE_PCT_729DAY);
        assertEq(iUSDC.totalSupplyExcluding(mkList(bob)), TEN_PCT_365DAY_1);
        assertEq(iUSDC.totalSupply(), TEN_PCT_365DAY_1+FIVE_PCT_729DAY);
    }

    function test_totalSupplyExcludingList() public {
        vm.startPrank(origamiMultisig);

        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);
        vm.warp(block.timestamp + 1 days);
        iUSDC.mint(bob, amount);

        vm.warp(block.timestamp + 364 days);

        IOrigamiDebtToken.DebtorPosition memory cache = iUSDC.getDebtorPosition(alice);
        assertEq(cache.principal, amount);
        assertEq(cache.interest, TWO_PCT_365DAY - amount);
        assertEq(cache.interestDelta, TWO_PCT_365DAY - amount);
        assertEq(cache.rate, aliceInterestRate);

        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0.1e18);
        vm.warp(block.timestamp + 365 days);

        // Only includes checkpoint data
        assertEq(iUSDC.totalSupplyExcluding(mkList(alice, bob)), 0);
        assertEq(iUSDC.totalSupply(), TWO_PCT_365DAY+amount);

        // Do a checkpoint and re-check
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (alice, bob);
        vm.expectEmit(address(iUSDC));
        emit Checkpoint(alice, uint128(amount), uint128(TEN_PCT_365DAY_1-amount));
        vm.expectEmit(address(iUSDC));
        emit Checkpoint(bob, uint128(amount), uint128(FIVE_PCT_729DAY-amount));
        iUSDC.checkpointDebtorsInterest(_debtors);

        assertEq(iUSDC.totalSupplyExcluding(mkList(alice, bob)), 0);
        assertEq(iUSDC.totalSupply(), TEN_PCT_365DAY_1+FIVE_PCT_729DAY);
    }
}
