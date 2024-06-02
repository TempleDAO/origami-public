pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";
import { IOrigamiLendingBorrower } from "contracts/interfaces/investments/lending/IOrigamiLendingBorrower.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

import { OrigamiLendingClerkTestBase, MockBorrower } from "./OrigamiLendingClerkBase.t.sol";
import { OrigamiLendingClerk } from "contracts/investments/lending/OrigamiLendingClerk.sol";
import { OrigamiLendingClerk } from "contracts/investments/lending/OrigamiLendingClerk.sol";
import { OrigamiCircuitBreakerAllUsersPerPeriod } from "contracts/common/circuitBreaker/OrigamiCircuitBreakerAllUsersPerPeriod.sol";
import { OrigamiIdleStrategyManager } from "contracts/investments/lending/idleStrategy/OrigamiIdleStrategyManager.sol";
import { OrigamiOToken } from "contracts/investments/OrigamiOToken.sol";
import { OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract OrigamiLendingClerkTestDepositWithdraw is OrigamiLendingClerkTestBase {
    event Deposit(address indexed fromAccount, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);

    function test_deposit_success() public {
        vm.startPrank(supplyManager);

        uint256 amount = 100e6;

        doMint(usdcToken, supplyManager, amount);
        usdcToken.approve(address(lendingClerk), amount);

        vm.expectEmit(address(lendingClerk));
        emit Deposit(supplyManager, amount);
        lendingClerk.deposit(amount);

        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), amount);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 100e18);
    }

    function test_withdraw_fail_noDebtNoSupply() public {
        vm.startPrank(supplyManager);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(usdcToken), 100e6, 0));
        lendingClerk.withdraw(100e6, alice);
    }

    function test_withdraw_fail_noDebtWithSupply() public {
        doMint(oUsdc, alice, 1_000e18);
        vm.startPrank(supplyManager);

        // Still fails in the idle strategy withdrawal
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUsdc), 100e18, 0));
        lendingClerk.withdraw(100e6, alice);
    }

    function test_withdraw_success_exact() public {
        uint256 amount = 100e6;
        doDeposit(amount);
        
        emit Withdraw(alice, 100e6);
        lendingClerk.withdraw(100e6, alice);

        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 0);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(alice)), 100e6);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 0);
    }

    function test_withdraw_success_moreDebt() public {
        uint256 amount = 150e6;
        doDeposit(amount);
        
        emit Withdraw(alice, 100e6);
        lendingClerk.withdraw(100e6, alice);

        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 50e6);
        assertEq(usdcToken.balanceOf(address(supplyManager)), 0);
        assertEq(usdcToken.balanceOf(address(alice)), 100e6);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 50e18);
    }

    function test_withdraw_fail_lessDebt() public {
        uint256 amount = 100e6;

        // Deal an extra amount to the idle strategy manager 
        doMint(usdcToken, address(idleStrategyManager), 50e6);

        // And deposit normally
        doDeposit(amount);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 150e6);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(usdcToken), 130e6, 100e6));
        lendingClerk.withdraw(130e6, alice);
    }

    function test_withdraw_fail_lessDebt_extraOusdc() public {
        uint256 amount = 100e6;

        // Deal an extra amount to the idle strategy manager 
        doMint(usdcToken, address(idleStrategyManager), 50e6);

        // And deposit normally
        doDeposit(amount);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 150e6);

        // Mint a bunch of extra oToken for whatever reason
        doMint(oUsdc, alice, 1_000e18);

        // Still reverts - this time from the idle strategy manager
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUsdc), 130e18, 100e18));
        lendingClerk.withdraw(130e6, alice);
    }

    function test_withdraw_fail_aboveMaxUtilisation_withCheckpoint() public {
        doDeposit(1_000e6);
        doBorrow(500e18, 250e6);

        vm.warp(block.timestamp + 30 days);

        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 1_000e6 - 250e6);
        assertEq(usdcToken.balanceOf(address(borrower)), 250e6);
        assertEq(usdcToken.balanceOf(address(alice)), 0);
        assertEq(oUsdc.balanceOf(alice), 1_000e18);

        uint256 expectedAvailable = 750e6;
        uint256 expectedIdleStrategyInterest = 3.0885337362385635e18;
        uint256 expectedBorrowerDebt = 252.639406412895888750e18;

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18);
            assertEq(lendingClerk.globalUtilisationRatio(), 0.25e18); // 250/1000 = 25% UR
            assertEq(idleStrategyManager.availableToWithdraw(), expectedAvailable);
            assertEq(iUsdc.totalSupply(), 1_000e18);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 750e18 + expectedIdleStrategyInterest);
            assertEq(lendingClerk.totalBorrowerDebt(), 1_000e18 - _scaleUp(expectedAvailable));
            assertEq(lendingClerk.totalAvailableToWithdraw(), expectedAvailable);
        }

        // Checkpoint the debt
        address[] memory _borrowers = new address[](1);
        _borrowers[0] = address(borrower);
        lendingClerk.refreshBorrowersInterestRate(_borrowers);
        assertEq(lendingClerk.totalBorrowerDebt(), expectedBorrowerDebt);

        // After the checkpoint, the global UR is higher (more borrower debt)
        // The totalAvailableToWithdraw is now less, the global available to borrow is less 
        // (also because the borrower debt is higher)
        uint256 expectedAvailable2 = 747.360593e6;
        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18);
            assertEq(lendingClerk.globalUtilisationRatio(), 0.252639406412895889e18); // 252.64/1000 = 25.26% UR
            assertEq(idleStrategyManager.availableToWithdraw(), 750e6);
            assertEq(iUsdc.totalSupply(), 750e18 + expectedIdleStrategyInterest + expectedBorrowerDebt);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 750e18 + expectedIdleStrategyInterest);
            assertEq(lendingClerk.totalBorrowerDebt(), expectedBorrowerDebt);
            assertEq(lendingClerk.totalAvailableToWithdraw(), expectedAvailable2);
        }

        // Can't withdraw anymore thant the totalAvailableToWithdraw
        vm.startPrank(supplyManager);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(usdcToken), expectedAvailable2+1, expectedAvailable2));
        lendingClerk.withdraw(expectedAvailable2+1, alice);

        vm.expectEmit(address(lendingClerk));
        emit Withdraw(alice, expectedAvailable2);
        lendingClerk.withdraw(expectedAvailable2, alice);

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18);
            assertEq(lendingClerk.globalUtilisationRatio(), 0.252639406412895889e18); // 252.64/1000 = 25.26% UR

            // reduced by the repaid amount
            assertEq(idleStrategyManager.availableToWithdraw(), 750e6 - expectedAvailable2);

            // reduced by the repaid amount (scaled up to 18 dp)
            assertEq(iUsdc.totalSupply(), 750e18 + expectedIdleStrategyInterest + expectedBorrowerDebt - _scaleUp(expectedAvailable2));
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 750e18 + expectedIdleStrategyInterest - _scaleUp(expectedAvailable2));

            assertEq(lendingClerk.totalBorrowerDebt(), iUsdc.totalSupply() - iUsdc.balanceOf(address(idleStrategyManager)));
            assertEq(lendingClerk.totalAvailableToWithdraw(), 750e6 - expectedAvailable2);
        }

        // Simulate the burn of oUSDC's too
        doBurn(oUsdc, alice, _scaleUp(expectedAvailable2));

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18 - _scaleUp(expectedAvailable2));
            assertEq(lendingClerk.globalUtilisationRatio(), 0.999999997676118235e18); // Just under 100% UR

            // reduced by the repaid amount
            assertEq(idleStrategyManager.availableToWithdraw(), 750e6 - expectedAvailable2);

            // reduced by the repaid amount (scaled up to 18 dp)
            assertEq(iUsdc.totalSupply(), 750e18 + expectedIdleStrategyInterest + expectedBorrowerDebt - _scaleUp(expectedAvailable2));
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 750e18 + expectedIdleStrategyInterest - _scaleUp(expectedAvailable2));

            assertEq(lendingClerk.totalBorrowerDebt(), expectedBorrowerDebt);
            assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
        }
    }

    function test_withdraw_fail_aboveMaxUtilisation_noCheckpoint() public {
        doDeposit(1_000e6);
        doBorrow(500e18, 250e6);

        vm.warp(block.timestamp + 30 days);

        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 1_000e6 - 250e6);
        assertEq(usdcToken.balanceOf(address(borrower)), 250e6);
        assertEq(usdcToken.balanceOf(address(alice)), 0);
        assertEq(oUsdc.balanceOf(alice), 1_000e18);

        uint256 expectedAvailable = 750e6;
        uint256 expectedIdleStrategyInterest = 3.0885337362385635e18;
        uint256 expectedBorrowerDebt = 252.639406412895888750e18;

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18);
            assertEq(lendingClerk.globalUtilisationRatio(), 0.25e18); // 250/1000 = 25% UR
            assertEq(idleStrategyManager.availableToWithdraw(), expectedAvailable);
            assertEq(iUsdc.totalSupply(), 1_000e18);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 750e18 + expectedIdleStrategyInterest);
            assertEq(lendingClerk.totalBorrowerDebt(), 1_000e18 - _scaleUp(expectedAvailable));
            assertEq(lendingClerk.totalAvailableToWithdraw(), expectedAvailable);
        }

        // Can't withdraw anymore thant the totalAvailableToWithdraw
        vm.startPrank(supplyManager);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(usdcToken), expectedAvailable+1, expectedAvailable));
        lendingClerk.withdraw(expectedAvailable+1, alice);

        vm.expectEmit(address(lendingClerk));
        emit Withdraw(alice, expectedAvailable);
        lendingClerk.withdraw(expectedAvailable, alice);

        // Simulate the burn of oUSDC's too
        doBurn(oUsdc, alice, _scaleUp(expectedAvailable));

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18 - _scaleUp(expectedAvailable));
            assertEq(lendingClerk.globalUtilisationRatio(), 1e18); // Now at 100% UR

            // reduced by the repaid amount
            assertEq(idleStrategyManager.availableToWithdraw(), 0);

            // reduced by the repaid amount (scaled up to 18 dp)
            assertEq(iUsdc.totalSupply(), 1_000e18 - _scaleUp(expectedAvailable) + expectedIdleStrategyInterest);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), expectedIdleStrategyInterest);

            assertEq(lendingClerk.totalBorrowerDebt(), 1_000e18 - _scaleUp(expectedAvailable)); // borrower debt still not checkpoint
            assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
        }

        // Now checkpoint the debt
        address[] memory _borrowers = new address[](1);
        _borrowers[0] = address(borrower);
        vm.startPrank(origamiMultisig);
        lendingClerk.refreshBorrowersInterestRate(_borrowers);
        assertEq(lendingClerk.totalBorrowerDebt(), expectedBorrowerDebt);

        {
            assertEq(oUsdc.circulatingSupply(), 1_000e18 - _scaleUp(expectedAvailable));
            // UR shows as slightly > 100% after the checkpoint. This is fine though
            // the new oUSDC will be minted to catch up to this.
            assertEq(lendingClerk.globalUtilisationRatio(), 1.010557625651583555e18);

            // reduced by the repaid amount
            assertEq(idleStrategyManager.availableToWithdraw(), 0);

            // reduced by the repaid amount (scaled up to 18 dp)
            assertEq(iUsdc.totalSupply(), expectedBorrowerDebt + expectedIdleStrategyInterest);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), expectedIdleStrategyInterest);

            assertEq(lendingClerk.totalBorrowerDebt(), expectedBorrowerDebt);
            assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
        }
    }
}

contract OrigamiLendingClerkTestBorrow is OrigamiLendingClerkTestBase {
    event Borrow(address indexed borrower, address indexed recipient, uint256 amount);
    event InterestRateSet(address indexed debtor, uint96 rate);

    function test_borrow_fail_noBorrower() public {
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.borrow(100e6, alice);
    }

    function test_borrow_fail_zeroCapacity() public {
        doDeposit(1_000e6);
        addBorrower(0);
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AboveMaxUtilisation.selector, type(uint256).max));
        lendingClerk.borrow(100e6, alice);
    }

    function test_borrow_fail_notEnoughBorrowerCapacity() public {
        doDeposit(1_000e6);
        addBorrower(100e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(80e6, alice);
        
        uint256 expectedUr = uint256(100e6+1) * 1e18 / 100e6;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AboveMaxUtilisation.selector, expectedUr));
        lendingClerk.borrow(20e6+1, alice);
    }

    function test_availableToBorrow() public {
        uint256 globalCapacity = 3_000_000e6;
        uint256 borrowAmount = 500_000e6;
        doDeposit(globalCapacity);
        addBorrower(1_000_000e18);
        vm.startPrank(address(borrower));

        // Capped to the debt ceiling
        assertEq(lendingClerk.availableToBorrow(address(borrower)), 1_000_000e6);
        lendingClerk.borrow(borrowAmount, alice);
        assertEq(lendingClerk.availableToBorrow(address(borrower)), 500_000e6);

        // Up the debt ceiling
        vm.startPrank(origamiMultisig);
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 3_000_000e18);

        // Capped to the circuit breaker remaining amount
        assertEq(lendingClerk.availableToBorrow(address(borrower)), 1_500_000e6);
    }

    function test_borrow_fail_notEnoughGlobalCapacity() public {
        uint256 globalCapacity = 100e6;
        uint256 borrowAmount = 80e6;
        doDeposit(globalCapacity);
        addBorrower(1_000e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(borrowAmount, alice);

        uint256 expectedIdleInterest = 1.025421e6; // 5% APY cont compounding on 20e6
        uint256 expectedBorrowerInterest = 8.807497e6; // ~10.444% APY cont compounding on 80e6

        // Move forward in time to accrue iUSDC
        {
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), _scaleUp(globalCapacity-borrowAmount));
            assertEq(iUsdc.balanceOf(address(borrower)), _scaleUp(borrowAmount));

            vm.warp(block.timestamp + 365 days);

            _scaleAndAssert(iUsdc.balanceOf(address(idleStrategyManager)), globalCapacity-borrowAmount+expectedIdleInterest);
            _scaleAndAssert(iUsdc.balanceOf(address(borrower)), borrowAmount+expectedBorrowerInterest);
        }

        // The debt hasn't been checkpoint -- so the total borrower debt doesn't 
        // include the accrued interest yet, just the 80e6 borrowed
        {
            _scaleAndAssert(lendingClerk.totalBorrowerDebt(), borrowAmount);
            assertEq(lendingClerk.totalAvailableToWithdraw(), 20e6);
            _scaleAndAssert(iUsdc.totalSupply(), globalCapacity);
            assertEq(lendingClerk.availableToBorrow(address(borrower)), 20e6);
            assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0.088807497622378286e18); // 88.88 / 1000
            assertEq(lendingClerk.globalUtilisationRatio(), 0.8e18); // 80 / 100
            assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), 0.104933749867909905e18);
            assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), 0.104933749867909905e18);
            assertEq(lendingClerk.calculateGlobalInterestRate(), 0.094444444444444445e18);
        }

        // Idle strategy still has an outstanding debt after the next borrow
        // The 5% APY (cont. compounding) on the 20e6 USDC, minus the 20e6 USDC 
        // principal which is transferred from idle strategy => borrower
        {
            uint256 newBorrowAmount = 20e6;
            uint256 expectedTotalBorrowerDebt = _scaleUp(borrowAmount + expectedBorrowerInterest + newBorrowAmount);
            assertEq(expectedTotalBorrowerDebt, 108.807497e18);

            uint256 expectedGlobalUr = OrigamiMath.mulDiv(
                expectedTotalBorrowerDebt,
                1e18,
                _scaleUp(globalCapacity),
                OrigamiMath.Rounding.ROUND_UP
            );
            assertEq(expectedGlobalUr, 1.088074970000000000e18);

            // The actual UR is slightly higher than this because of rounding
            uint256 actualGlobalUr = 1.088074976223782856e18;

            // Can't borrow more than the capacity
            vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AboveMaxUtilisation.selector, actualGlobalUr));
            lendingClerk.borrow(newBorrowAmount, alice);
        }

        // If the borrower's IR is manually refreshed then the checkpoint happens
        // For the borrower and also the idle strategy
        {
            address[] memory borrowers = new address[](1);
            borrowers[0] = address(borrower);

            vm.startPrank(origamiMultisig);
            lendingClerk.refreshBorrowersInterestRate(borrowers);
            _scaleAndAssert(lendingClerk.totalBorrowerDebt(), borrowAmount + expectedBorrowerInterest);
            _scaleAndAssert(iUsdc.totalSupply(), globalCapacity + expectedIdleInterest + expectedBorrowerInterest);
        }

        // Borrower has already borrowed 80e6 (so 20e6 left out of the total 100e6)
        // But the borrower has also accrued interest, which impacts what capacity is left
        // It's correctly rounded down
        uint256 maxBorrowable = globalCapacity - borrowAmount - expectedBorrowerInterest - 1;
        assertEq(maxBorrowable, 11.192502e6);
        {           
            _scaleAndAssert(lendingClerk.globalUtilisationRatio(), OrigamiMath.mulDiv(
                borrowAmount+expectedBorrowerInterest,
                1e6,
                globalCapacity,
                OrigamiMath.Rounding.ROUND_UP
            ));
            _scaleAndAssert(iUsdc.balanceOf(address(borrower)), borrowAmount+expectedBorrowerInterest);
            assertEq(usdcToken.balanceOf(address(alice)), borrowAmount);
            _scaleAndAssert(lendingClerk.borrowerUtilisationRatio(address(borrower)), (borrowAmount+expectedBorrowerInterest) * 1e6 / 1_000e6);

            // 20e6 USDC still left in the idle strategy manager
            assertEq(idleStrategyManager.availableToWithdraw(), globalCapacity - borrowAmount);
            assertEq(lendingClerk.availableToBorrow(address(borrower)), globalCapacity - borrowAmount - expectedBorrowerInterest - 1);

            // The balance of iUSDC for idleStrategyManager increased by the idle interest
            _scaleAndAssert(iUsdc.balanceOf(address(idleStrategyManager)), globalCapacity - borrowAmount + expectedIdleInterest);

            assertEq(lendingClerk.totalAvailableToWithdraw(), maxBorrowable);

            assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), 0.104933749867909905e18);
            assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), 0.104933749867909905e18);
            assertEq(lendingClerk.calculateGlobalInterestRate(), 0.099337498679099048e18);
        }

        vm.startPrank(address(borrower));
        lendingClerk.borrow(maxBorrowable, alice);

        {
            // Ever so slightly less than 100%, because there's a little less debt
            assertEq(lendingClerk.globalUtilisationRatio(), 0.999999996223782856e18);
            assertEq(iUsdc.balanceOf(address(borrower)), 99.999999622378285600e18);
            assertEq(usdcToken.balanceOf(address(alice)), borrowAmount + maxBorrowable);
            assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0.099999999622378286e18); // 100e6 * 1e18 / 1_000e6

            assertEq(idleStrategyManager.availableToWithdraw(), globalCapacity - borrowAmount - maxBorrowable);
            assertEq(lendingClerk.availableToBorrow(address(borrower)), 0);

            _scaleAndAssert(9.832919927520480780e18, globalCapacity - borrowAmount - maxBorrowable + expectedIdleInterest);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 9.832919927520480780e18);
            assertEq(lendingClerk.totalAvailableToWithdraw(), 0);

            // Almost at the max Global IR
            assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), 0.199999996223782856e18);
            assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), 0.105555555534576572e18);
            assertEq(lendingClerk.calculateGlobalInterestRate(), 0.199999996223782856e18);
        }

        // Any more takes it over the cap
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AboveMaxUtilisation.selector, 1.000000006223782856e18));
        lendingClerk.borrow(1, alice);
    }

    function test_borrow_fail_zeroAmount() public {
        addBorrower(100e18);
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        lendingClerk.borrow(0, alice);
    }

    function test_borrow_fail_globalBorrowPaused() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.setGlobalPaused(true, false);

        doDeposit(1_000e6);
        addBorrower(100e18);

        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowPaused.selector));
        lendingClerk.borrow(100e6, alice);
    }

    function test_borrow_fail_borrowerPaused() public {
        doDeposit(1_000e6);
        addBorrower(100e18);

        vm.startPrank(origamiMultisig);
        lendingClerk.setBorrowerPaused(address(borrower), true, false);

        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowPaused.selector));
        lendingClerk.borrow(100e6, alice);
    }

    function test_borrow_success() public {
        doDeposit(1_000e6);
        addBorrower(100e18);

        vm.startPrank(address(borrower));
        
        vm.expectEmit(address(lendingClerk));
        emit Borrow(address(borrower), alice, 80e6);
        vm.expectEmit(address(iUsdc));
        // A little higher than the 10% min
        uint96 expectedNewIr = 0.144444444444444445e18;
        emit InterestRateSet(address(borrower), expectedNewIr);
        lendingClerk.borrow(80e6, alice);

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0.8e18);
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 80e6);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 1_000e6-80e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 80e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 1_000e18-80e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 80e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, expectedNewIr);
    }

    function test_borrow_fail_notEnoughDebt() public {
        {
            // 950 USDC straight transfer into the idle strategy manager
            // instead of a proper deposit()
            doMint(usdcToken, address(idleStrategyManager), 950e6);

            // Another 50 proper deposit (so 50 iUSDC debt for idle strategy)
            doDeposit(50e6);

            assertEq(usdcToken.balanceOf(address(borrower)), 0);
            assertEq(usdcToken.balanceOf(alice), 0);
            assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
            assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 1_000e6);

            assertEq(iUsdc.balanceOf(address(borrower)), 0);
            assertEq(iUsdc.balanceOf(alice), 0);
            assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 50e18);
        }

        addBorrower(100e18);

        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(iUsdc), 80e18, 50e18));
        lendingClerk.borrow(80e6, alice);
    }

    function test_borrow_fail_circuitBreaker() public {
        doDeposit(5_000_000e6);
        addBorrower(5_000_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrow(2_000_000e6, alice);

        vm.expectRevert(abi.encodeWithSelector(OrigamiCircuitBreakerAllUsersPerPeriod.CapBreached.selector, 2_000_000e6 + 1, 2_000_000e6));
        lendingClerk.borrow(1, alice);
    }

    function test_borrowMax_fail_noBorrower() public {
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.borrowMax(alice);
    }

    function test_borrowMax_belowBorrowersCap() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        
        vm.expectEmit(address(lendingClerk));
        emit Borrow(address(borrower), alice, 1_000e6);
        vm.expectEmit(address(iUsdc));
        // Now at 100% UR
        uint96 expectedNewIr = BORROWER_IR_AT_100_UR;
        emit InterestRateSet(address(borrower), expectedNewIr);
        lendingClerk.borrowMax(alice);

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 1e18);
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 1_000e6);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 4_000e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 1_000e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 4_000e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 1_000e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, expectedNewIr);
    }

    function test_borrowMax_atBorrowersCap() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrowMax(alice);

        // A no-op since there's no capacity left
        lendingClerk.borrowMax(alice);

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 1e18);
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 1_000e6);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 4_000e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 1_000e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 4_000e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 1_000e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, BORROWER_IR_AT_100_UR);
    }

    function test_borrowMax_aboveBorrowersCap() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrowMax(alice);

        // Reduce the capacity
        vm.startPrank(origamiMultisig);
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 200e18);

        // A no-op since there's no capacity left
        vm.startPrank(address(borrower));
        lendingClerk.borrowMax(alice);

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 5e18); // 500% UR
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 1_000e6);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 4_000e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 1_000e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 4_000e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 1_000e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, BORROWER_IR_AT_100_UR);
    }

    function test_borrowMax_hitCircuitBreaker() public {
        doDeposit(5_000_000e6);
        addBorrower(3_000_000e18);

        uint256 _availableToBorrow = lendingClerk.availableToBorrow(address(borrower));
        assertEq(_availableToBorrow, 2_000_000e6);
        vm.startPrank(address(borrower));
        uint256 actuallyBorrowed = lendingClerk.borrowMax(alice);
        assertEq(actuallyBorrowed, _availableToBorrow);
        assertEq(usdcToken.balanceOf(alice), _availableToBorrow);
    }
}

contract OrigamiLendingClerkTestRepay is OrigamiLendingClerkTestBase {
    event Repay(address indexed borrower, address indexed from, uint256 amount);
    event InterestRateSet(address indexed debtor, uint96 rate);

    function test_repay_fail_noBorrower() public {
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.repay(100e6, address(borrower));
    }

    function test_repay_fail_globalRepayPaused() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.setGlobalPaused(false, true);

        doDeposit(1_000e6);
        addBorrower(1_000e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(100e6, address(borrower));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.RepayPaused.selector));
        lendingClerk.repay(100e6, address(borrower));
    }

    function test_repay_fail_borrowerPaused() public {
        doDeposit(1_000e6);
        addBorrower(100e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(100e6, address(borrower));

        vm.startPrank(origamiMultisig);
        lendingClerk.setBorrowerPaused(address(borrower), false, true);

        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.RepayPaused.selector));
        lendingClerk.repay(100e6, address(borrower));
    }

    function test_repay_success_noDebt() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.repay(100e6, address(borrower));

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 5_000e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 0);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 5_000e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 0);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, 0);
    }

    function test_repay_success_withDebt() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrow(500e6, address(borrower));

        vm.warp(block.timestamp + 30 days);

        usdcToken.approve(address(lendingClerk), 100e6);

        // A little higher than the 10% min
        uint96 expectedNewIr = 0.122515489601432877e18;

        vm.expectEmit(address(lendingClerk));
        emit Repay(address(borrower), address(borrower), 100e6);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), expectedNewIr);
        lendingClerk.repay(100e6, address(borrower));

        // roughly (500-100) / 5000 = 8%
        assertEq(lendingClerk.globalUtilisationRatio(), 0.081055762565158356e18);
        // roughly (500-100) / 1000 = 40%
        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0.405278812825791778e18);
        assertEq(usdcToken.balanceOf(address(borrower)), 400e6);
        assertEq(usdcToken.balanceOf(alice), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 5_000e6-500e6+100e6);
        assertEq(idleStrategyManager.availableToWithdraw(), 5_000e6-500e6+100e6);
        assertEq(lendingClerk.availableToBorrow(address(borrower)), 594.721187e6); // ~1_000 - 500 + 100
        assertEq(lendingClerk.totalAvailableToWithdraw(), 4_594.721187e6); // ~5_000 - 500 + 100

        assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), expectedNewIr);
        assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), expectedNewIr);
        assertEq(lendingClerk.calculateGlobalInterestRate(), 0.054503097920286576e18);

        assertEq(iUsdc.balanceOf(address(borrower)), 405.278812825791777500e18);
        assertEq(lendingClerk.borrowerDebt(address(borrower)), 405.278812825791777500e18);
        assertEq(lendingClerk.borrowerDebt(address(bob)), 0); // unknown borrower
        assertEq(lendingClerk.borrowerDebt(address(idleStrategyManager)), 4_618.531202417431381000e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 4_618.531202417431381000e18);

        // Interest was paid off first
        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 405.278812825791777500e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, expectedNewIr);
    }

    function test_repay_success_onBehalfOf() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrow(500e6, alice);
        assertEq(usdcToken.balanceOf(alice), 500e6);
        assertEq(iUsdc.balanceOf(address(borrower)), 500e18);

        vm.startPrank(origamiMultisig);
        setExplicitAccess(lendingClerk, bob, OrigamiLendingClerk.repay.selector, true);

        vm.startPrank(bob);
        doMint(usdcToken, bob, 100e6);
        usdcToken.approve(address(lendingClerk), 100e6);

        // A little higher than the 10% min
        uint96 expectedNewIr = 0.122222222222222223e18;

        vm.expectEmit(address(lendingClerk));
        emit Repay(address(borrower), bob, 100e6);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), expectedNewIr);

        lendingClerk.repay(100e6, address(borrower));

        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0.4e18);
        assertEq(usdcToken.balanceOf(address(borrower)), 0);
        assertEq(usdcToken.balanceOf(alice), 500e6);
        assertEq(usdcToken.balanceOf(bob), 0);
        assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
        assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 5_000e6-500e6+100e6);

        assertEq(iUsdc.balanceOf(address(borrower)), 400e18);
        assertEq(iUsdc.balanceOf(alice), 0);
        assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
        assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 5_000e18-500e18+100e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 400e18);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, expectedNewIr);
    }

    function test_repay_success_capped() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrow(500e6, alice);
        assertEq(usdcToken.balanceOf(alice), 500e6);

        vm.warp(block.timestamp + 30 days);

        vm.startPrank(origamiMultisig);
        setExplicitAccess(lendingClerk, bob, OrigamiLendingClerk.repay.selector, true);

        vm.startPrank(bob);
        doMint(usdcToken, bob, 1_000e6);
        usdcToken.approve(address(lendingClerk), 1_000e6);

        // All repaid
        uint96 expectedNewIr = BORROWER_IR_AT_0_UR;

        // Note the amount repaid by the user is ROUNDED UP
        uint256 expectedBorrowerInterest =      5.278812825791777500e18;
        uint256 expectedRepayInterest = 5.278813e6;
        uint256 expectedIdleInterest =  23.810015243223158500e18;
        assertEq(iUsdc.balanceOf(address(borrower)), 500e18 + expectedBorrowerInterest);

        vm.expectEmit(address(lendingClerk));
        emit Repay(address(borrower), bob, 500e6 + expectedRepayInterest);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), expectedNewIr);
        lendingClerk.repay(1_000e6, address(borrower));

        {
            assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0);
            assertEq(usdcToken.balanceOf(address(borrower)), 0);
            assertEq(usdcToken.balanceOf(alice), 500e6);
            assertEq(usdcToken.balanceOf(bob), 1_000e6 - 500e6 - expectedRepayInterest);
            assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
            assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 5_000e6 + expectedRepayInterest);

            assertEq(iUsdc.balanceOf(address(borrower)), 0);
            assertEq(iUsdc.balanceOf(alice), 0);
            assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 5_000e18 + expectedIdleInterest);

            IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
            assertEq(debtPosition.principal, 0);
            assertEq(debtPosition.interest, 0);
            assertEq(debtPosition.interestDelta, 0);
            assertEq(debtPosition.rate, expectedNewIr);

            assertEq(idleStrategyManager.availableToWithdraw(), 5_000e6 + expectedRepayInterest);
            assertEq(lendingClerk.availableToBorrow(address(borrower)), 1_000e6);
            assertEq(lendingClerk.totalAvailableToWithdraw(), 5_000e6);

            assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), expectedNewIr);
            assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), expectedNewIr);
            assertEq(lendingClerk.calculateGlobalInterestRate(), GLOBAL_IR_AT_0_UR);
        }

        // Nothing left to repay
        {
            lendingClerk.repay(1_000e6, address(borrower));
            assertEq(iUsdc.balanceOf(address(borrower)), 0);
        }

        // Now assume 80% of the extra yield is now minted as new oUSDC
        uint256 newOusdc = expectedIdleInterest * 8/10;
        doMint(oUsdc, alice, newOusdc);

        {
            assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0);
            assertEq(usdcToken.balanceOf(address(borrower)), 0);
            assertEq(usdcToken.balanceOf(alice), 500e6);
            assertEq(usdcToken.balanceOf(bob), 1_000e6 - 500e6 - expectedRepayInterest);
            assertEq(usdcToken.balanceOf(address(lendingClerk)), 0);
            assertEq(usdcToken.balanceOf(address(idleStrategyManager)), 5_000e6 + expectedRepayInterest);

            assertEq(iUsdc.balanceOf(address(borrower)), 0);
            assertEq(iUsdc.balanceOf(alice), 0);
            assertEq(iUsdc.balanceOf(address(lendingClerk)), 0);
            assertEq(iUsdc.balanceOf(address(idleStrategyManager)), 5_000e18 + expectedIdleInterest);

            IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
            assertEq(debtPosition.principal, 0);
            assertEq(debtPosition.interest, 0);
            assertEq(debtPosition.interestDelta, 0);
            assertEq(debtPosition.rate, expectedNewIr);

            assertEq(idleStrategyManager.availableToWithdraw(), 5_000e6 + expectedRepayInterest);
            assertEq(lendingClerk.availableToBorrow(address(borrower)), 1_000e6);
            // now uses the max in idle
            assertEq(lendingClerk.totalAvailableToWithdraw(), 5_000e6 + expectedRepayInterest);

            assertEq(lendingClerk.calculateCombinedInterestRate(address(borrower)), expectedNewIr);
            assertEq(lendingClerk.calculateBorrowerInterestRate(address(borrower)), expectedNewIr);
            assertEq(lendingClerk.calculateGlobalInterestRate(), GLOBAL_IR_AT_0_UR);
        }
    }

    function test_repay_fail_notEnough() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);

        vm.startPrank(address(borrower));
        lendingClerk.borrow(500e6, address(borrower));

        vm.startPrank(address(origamiMultisig));
        usdcToken.approve(address(lendingClerk), 1_000e6);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        lendingClerk.repay(1_000e6, address(borrower));
    }

}

contract OrigamiLendingClerkTestViews is OrigamiLendingClerkTestBase {
    function test_globalDebtCeiling_edgeConditions() public {
        // Supply but without the oUSDC mint
        uint256 supplyAmount = 5_000e6;
        {
            vm.startPrank(supplyManager);
            doMint(usdcToken, supplyManager, supplyAmount);
            usdcToken.approve(address(lendingClerk), supplyAmount);
            lendingClerk.deposit(supplyAmount);
        }
        addBorrower(1_000e18);
        assertEq(lendingClerk.borrowerDebtCeiling(address(borrower)), 1_000e18);
        assertEq(lendingClerk.borrowerDebt(address(borrower)), 0);
        assertEq(lendingClerk.borrowerDebt(address(idleStrategyManager)), 5_000e18);

        // No debt, so UR = 0
        assertEq(lendingClerk.globalUtilisationRatio(), 0);
        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), 0);

        // No oUSDC, so just one wei will give a UR of uint256.max
        vm.startPrank(address(borrower));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AboveMaxUtilisation.selector, type(uint256).max));
        lendingClerk.borrow(1, address(this));

        // Now do the oUSDC mint        
        doMint(oUsdc, alice, supplyAmount * 1e12);

        lendingClerk.borrow(1, address(this));
        assertEq(lendingClerk.globalUtilisationRatio(), _scaleUp(1) * 1e18 / 5_000e18);
        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), _scaleUp(1) * 1e18 / 1_000e18);
        assertEq(lendingClerk.borrowerDebt(address(borrower)), _scaleUp(1));
        assertEq(lendingClerk.borrowerDebt(address(idleStrategyManager)), 4_999.999999e18);

        // Reduce the debt ceiling for borrower to zero
        vm.startPrank(origamiMultisig);
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 0);
        assertEq(lendingClerk.borrowerDebtCeiling(address(borrower)), 0);
        assertEq(lendingClerk.globalUtilisationRatio(), _scaleUp(1) * 1e18 / 5_000e18);
        assertEq(lendingClerk.borrowerUtilisationRatio(address(borrower)), type(uint256).max);
    }

    function test_borrowerBalanceSheet_unknownBorrower() public {
        (
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances,
            uint256 debtTokenBalance
        ) = lendingClerk.borrowerBalanceSheet(bob);

        assertEq(assetBalances.length, 0);
        assertEq(debtTokenBalance, 0);
    }

    function test_borrowerBalanceSheet_knownBorrower() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);
        borrower.borrow(123e6);

        (
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances,
            uint256 debtTokenBalance
        ) = lendingClerk.borrowerBalanceSheet(address(borrower));

        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(usdcToken));
        assertEq(assetBalances[0].balance, 123e6);
        assertEq(debtTokenBalance, 123e18);

        vm.warp(block.timestamp + 30 days);

        (
            assetBalances,
            debtTokenBalance
        ) = lendingClerk.borrowerBalanceSheet(address(borrower));

        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(usdcToken));
        assertEq(assetBalances[0].balance, 123e6);
        assertEq(debtTokenBalance, 124.084796829712940553e18);
    }

    function test_borrowerBalanceSheet_idleStrategyManager() public {
        doDeposit(5_000e6);
        addBorrower(1_000e18);
        borrower.borrow(123e6);

        (
            IOrigamiLendingBorrower.AssetBalance[] memory assetBalances,
            uint256 debtTokenBalance
        ) = lendingClerk.borrowerBalanceSheet(address(idleStrategyManager));

        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(usdcToken));
        assertEq(assetBalances[0].balance, 5_000e6-123e6);
        assertEq(debtTokenBalance, 4_877e18);

        vm.warp(block.timestamp + 30 days);

        (
            assetBalances,
            debtTokenBalance
        ) = lendingClerk.borrowerBalanceSheet(address(idleStrategyManager));

        assertEq(assetBalances.length, 1);
        assertEq(assetBalances[0].asset, address(usdcToken));
        assertEq(assetBalances[0].balance, 5_000e6-123e6);
        assertEq(debtTokenBalance, 4_897.083705375513965586e18);
    }
}

contract OrigamiLendingClerkTest18dpAsset is OrigamiLendingClerkTestBase {

    function test_scale18dpAsset() public {
        DummyMintableToken daiToken = new DummyMintableToken(origamiMultisig, "Deposit Token", "token", 18);
        OrigamiOToken oDai = new OrigamiOToken(origamiMultisig, "Origami DAI Token", "oDAI");
        OrigamiIdleStrategyManager daiIdleStrategyManager = new OrigamiIdleStrategyManager(origamiMultisig, address(daiToken));
        OrigamiDebtToken iDai = new OrigamiDebtToken("Origami iDAI", "iDAI", origamiMultisig);
        OrigamiCircuitBreakerAllUsersPerPeriod cbDaiBorrow = new OrigamiCircuitBreakerAllUsersPerPeriod(origamiMultisig, address(cbProxy), 26 hours, 13, 2_000_000e18);

        OrigamiLendingClerk daiLendingClerk = new OrigamiLendingClerk(
            origamiMultisig, 
            address(daiToken), 
            address(oDai), 
            address(daiIdleStrategyManager),
            address(iDai),
            address(cbProxy),
            supplyManager,
            address(globalInterestRateModel)
        );
        MockBorrower daiBorrower = new MockBorrower(address(daiToken), address(daiLendingClerk));

        {
            // Setup the circuit breaker for daily borrows of USDC
            vm.startPrank(origamiMultisig);
            cbProxy.setIdentifierForCaller(address(daiLendingClerk), "BORROW");
            cbProxy.setCircuitBreaker(BORROW, address(daiToken), address(cbDaiBorrow));

            // Allow the LendingManager allocate/withdraw from the idle strategy
            setExplicitAccess(
                daiIdleStrategyManager, 
                address(daiLendingClerk), 
                OrigamiIdleStrategyManager.allocate.selector, 
                OrigamiIdleStrategyManager.withdraw.selector, 
                true
            );

            // Allow the lendingClerk to mint iUSDC
            iDai.setMinter(address(daiLendingClerk), true);
            daiLendingClerk.setIdleStrategyInterestRate(IDLE_STRATEGY_IR);

            vm.stopPrank();
        }

        // Deposit
        uint256 supplyAmount = 123_333.123123123123123126e18;
        {
            vm.startPrank(supplyManager);
            doMint(daiToken, supplyManager, supplyAmount);
            daiToken.approve(address(daiLendingClerk), supplyAmount);
            daiLendingClerk.deposit(supplyAmount);

            // A new supply will only come from an oDai mint
            doMint(oDai, alice, supplyAmount);
        }

        // Add borrower
        uint256 borrowerCeiling = 55_555.555555555555555556e18;
        {
            vm.startPrank(origamiMultisig);
            daiLendingClerk.addBorrower(address(daiBorrower), address(borrowerInterestRateModel), borrowerCeiling);
        }

        uint256 borrowAmount = 9_999.999999999999999999e18;
        daiBorrower.borrow(borrowAmount);

        uint256 expectedNewIr = 0.11e18;
        {
            // roughly 10k / 123.3k = 8%
            assertEq(daiLendingClerk.globalUtilisationRatio(), 0.081081219276487689e18);
            // roughly 10k / 55.5k
            assertEq(daiLendingClerk.borrowerUtilisationRatio(address(daiBorrower)), 0.180000000000000000e18);
            assertEq(daiToken.balanceOf(address(daiBorrower)), borrowAmount);
            assertEq(daiToken.balanceOf(address(daiLendingClerk)), 0);
            assertEq(daiToken.balanceOf(address(daiIdleStrategyManager)), supplyAmount-borrowAmount);
            assertEq(daiIdleStrategyManager.availableToWithdraw(), supplyAmount-borrowAmount);
            assertEq(daiLendingClerk.availableToBorrow(address(daiBorrower)), borrowerCeiling-borrowAmount);
            assertEq(daiLendingClerk.totalAvailableToWithdraw(), supplyAmount - borrowAmount);

            assertEq(daiLendingClerk.calculateCombinedInterestRate(address(daiBorrower)), expectedNewIr);
            assertEq(daiLendingClerk.calculateBorrowerInterestRate(address(daiBorrower)), expectedNewIr);
            assertEq(daiLendingClerk.calculateGlobalInterestRate(), 0.054504512182027094e18);

            assertEq(iDai.balanceOf(address(daiBorrower)), borrowAmount);
            assertEq(daiLendingClerk.borrowerDebt(address(daiBorrower)), borrowAmount);
            assertEq(daiLendingClerk.borrowerDebt(address(daiIdleStrategyManager)), 113_333.123123123123123127e18);
            assertEq(iDai.balanceOf(address(daiIdleStrategyManager)), supplyAmount - borrowAmount);

            IOrigamiDebtToken.DebtorPosition memory debtPosition = iDai.getDebtorPosition(address(daiBorrower));
            assertEq(debtPosition.principal, borrowAmount);
            assertEq(debtPosition.interest, 0);
            assertEq(debtPosition.interestDelta, 0);
            assertEq(debtPosition.rate, expectedNewIr);
        }

        vm.warp(block.timestamp + 30 days);
        uint256 repayAmount = 1_000e18;
        vm.startPrank(address(daiBorrower));
        daiToken.approve(address(daiLendingClerk), repayAmount);
        daiLendingClerk.repay(repayAmount, address(daiBorrower));

        uint256 expectedNewIr2 = 0.109090820900487625e18;
        uint256 expectedInterest = 90.820900487624409999e18;
        {
            assertEq(daiLendingClerk.globalUtilisationRatio(), 0.073709484283571434e18);
            assertEq(daiLendingClerk.borrowerUtilisationRatio(address(daiBorrower)), 0.163634776208777240e18);
            assertEq(daiToken.balanceOf(address(daiBorrower)), borrowAmount - repayAmount);
            assertEq(daiToken.balanceOf(address(daiLendingClerk)), 0);
            assertEq(daiToken.balanceOf(address(daiIdleStrategyManager)), supplyAmount - borrowAmount + repayAmount);
            assertEq(daiIdleStrategyManager.availableToWithdraw(), supplyAmount - borrowAmount + repayAmount);
            assertEq(daiLendingClerk.availableToBorrow(address(daiBorrower)), borrowerCeiling - borrowAmount - expectedInterest + repayAmount);
            assertEq(daiLendingClerk.totalAvailableToWithdraw(), supplyAmount - borrowAmount - expectedInterest + repayAmount);

            assertEq(daiLendingClerk.calculateCombinedInterestRate(address(daiBorrower)), expectedNewIr2);
            assertEq(daiLendingClerk.calculateBorrowerInterestRate(address(daiBorrower)), expectedNewIr2);
            assertEq(daiLendingClerk.calculateGlobalInterestRate(), 0.054094971349087302e18);

            assertEq(iDai.balanceOf(address(daiBorrower)), borrowAmount + expectedInterest - repayAmount);
            assertEq(daiLendingClerk.borrowerDebt(address(daiBorrower)), borrowAmount + expectedInterest - repayAmount);
            assertEq(daiLendingClerk.borrowerDebt(address(daiIdleStrategyManager)), 114_799.834022055182581747e18);
            assertEq(iDai.balanceOf(address(daiIdleStrategyManager)), 114_799.834022055182581747e18);

            IOrigamiDebtToken.DebtorPosition memory debtPosition = iDai.getDebtorPosition(address(daiBorrower));
            assertEq(debtPosition.principal, borrowAmount + expectedInterest - repayAmount);
            assertEq(debtPosition.interest, 0);
            assertEq(debtPosition.interestDelta, 0);
            assertEq(debtPosition.rate, expectedNewIr2);
        }
    }
}