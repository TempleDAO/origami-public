pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiIdleStrategyTestBase } from "./OrigamiIdleStrategyTestBase.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiIdleStrategyManagerTestAdmin is OrigamiIdleStrategyTestBase {
    event IdleStrategySet(address indexed idleStrategy);
    event DepositsEnabledSet(bool value);
    event ThresholdsSet(uint256 depositThreshold, uint256 withdrawalBuffer);

    function test_initialization() public {
        assertEq(address(manager.owner()), origamiMultisig);
        assertEq(manager.version(), "1.0.0");
        assertEq(manager.name(), "IdleStrategyManager");
        assertEq(address(manager.asset()), address(asset));

        // no idle strategy by default
        assertEq(address(manager.idleStrategy()), address(0));
        assertEq(manager.depositsEnabled(), false);
        assertEq(manager.depositThreshold(), 0);
        assertEq(manager.withdrawalBuffer(), 0);
    }

    function test_setIdleStrategy_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setIdleStrategy(address(0));
    }

    function test_setIdleStrategy() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit IdleStrategySet(address(idleStrategy));
        manager.setIdleStrategy(address(idleStrategy));
        assertEq(address(manager.idleStrategy()), address(idleStrategy));
        assertEq(asset.allowance(address(manager), address(idleStrategy)), type(uint256).max);

        vm.expectEmit(address(manager));
        emit IdleStrategySet(bob);
        manager.setIdleStrategy(bob);
        assertEq(address(manager.idleStrategy()), bob);
        assertEq(asset.allowance(address(manager), address(idleStrategy)), 0);
        assertEq(asset.allowance(address(manager), bob), type(uint256).max);
    }

    function test_setDepositsEnabled() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit DepositsEnabledSet(true);
        manager.setDepositsEnabled(true);
        assertEq(manager.depositsEnabled(), true);
    }

    function test_setThresholds() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit ThresholdsSet(123e18, 1.12e18);
        manager.setThresholds(123e18, 1.12e18);
        assertEq(manager.depositThreshold(), 123e18);
        assertEq(manager.withdrawalBuffer(), 1.12e18);
    }

    function test_fail_recoverToken() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(asset)));
        manager.recoverToken(address(asset), alice, 100e18);
    }

    function test_recoverToken() public {
        check_recoverToken(address(manager));
    }
}

contract OrigamiIdleStrategyManagerTestAccess is OrigamiIdleStrategyTestBase {
    function test_setIdleStrategy_access() public {
        expectElevatedAccess();
        manager.setIdleStrategy(alice);
    }

    function test_setDepositsEnabled_access() public {
        expectElevatedAccess();
        manager.setDepositsEnabled(true);
    }

    function test_setThresholds_access() public {
        expectElevatedAccess();
        manager.setThresholds(100, 100);
    }

    function test_allocate_access() public {
        expectElevatedAccess();
        manager.allocate(100);
    }

    function test_withdraw_access() public {
        expectElevatedAccess();
        manager.withdraw(100, alice);
    }

    function test_allocateFromManager_access() public {
        expectElevatedAccess();
        manager.allocateFromManager(100);
    }

    function test_withdrawToManager_access() public {
        expectElevatedAccess();
        manager.withdrawToManager(100);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiIdleStrategyManagerTestAllocate is OrigamiIdleStrategyTestBase {
    event Allocated(uint256 amount, uint256 idleStrategyAmount);
    event Withdrawn(address indexed recipient, uint256 amount, uint256 idleStrategyAmount);

    function test_allocate_noAllowance() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert("ERC20: insufficient allowance");
        manager.allocate(100e18);
    }

    function test_allocate_noDeposit() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        deal(address(asset), origamiMultisig, amount);
        asset.approve(address(manager), amount);
        
        vm.expectEmit(address(manager));
        emit Allocated(amount, 0);
        manager.allocate(amount);

        assertEq(asset.balanceOf(address(manager)), amount);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);
        assertEq(manager.availableToWithdraw(), amount);
        checkLatestAssetBalances(amount);
        checkCheckpointAssetBalances(amount);
    }

    function test_allocate_withDeposit_overThresholdFresh() public {
        vm.startPrank(origamiMultisig);
        addThresholds(75e18, 20e18);

        uint256 amount = 100e18;
        deal(address(asset), origamiMultisig, amount);
        asset.approve(address(manager), amount);
        
        vm.expectEmit(address(manager));
        emit Allocated(amount, 25e18);
        manager.allocate(amount);

        assertEq(asset.balanceOf(address(manager)), 75e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 25e18);
        // 75e18 in manager + 80% of the 25e18 in idle strategy
        assertEq(manager.availableToWithdraw(), 75e18 + 20e18);
        checkLatestAssetBalances(amount);
        checkCheckpointAssetBalances(amount);
    }

    function test_allocate_withDeposit_overThresholdWithExisting() public {
        vm.startPrank(origamiMultisig);
        addThresholds(75e18, 20e18);

        uint256 amount = 100e18;
        deal(address(asset), origamiMultisig, amount);
        deal(address(asset), address(manager), amount);
        asset.approve(address(manager), amount);
        
        vm.expectEmit(address(manager));
        emit Allocated(amount, amount+25e18);
        manager.allocate(amount);

        assertEq(asset.balanceOf(address(manager)), 75e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), amount+25e18);
        // 75e18 in manager + 80% of the 125e18 in idle strategy
        assertEq(manager.availableToWithdraw(), 75e18 + 100e18);
        checkLatestAssetBalances(2*amount);
        checkCheckpointAssetBalances(2*amount);
    }

    function test_allocate_withDeposit_underThresholdFresh() public {
        vm.startPrank(origamiMultisig);
        addThresholds(175e18, 20e18);

        uint256 amount = 100e18;
        deal(address(asset), origamiMultisig, amount);
        asset.approve(address(manager), amount);
        
        vm.expectEmit(address(manager));
        emit Allocated(amount, 0);
        manager.allocate(amount);

        assertEq(asset.balanceOf(address(manager)), amount);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);
        assertEq(manager.availableToWithdraw(), amount);
        checkLatestAssetBalances(amount);
        checkCheckpointAssetBalances(amount);
    }

    function test_allocate_withDeposit_underThresholdExisting() public {
        vm.startPrank(origamiMultisig);
        addThresholds(200e18, 20e18);

        uint256 amount = 100e18;
        deal(address(asset), origamiMultisig, amount);
        deal(address(asset), address(manager), amount);
        asset.approve(address(manager), amount);
        
        vm.expectEmit(address(manager));
        emit Allocated(amount, 0);
        manager.allocate(amount);

        assertEq(asset.balanceOf(address(manager)), 2*amount);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);
        assertEq(manager.availableToWithdraw(), 2*amount);
        checkLatestAssetBalances(2*amount);
        checkCheckpointAssetBalances(2*amount);
    }

    function test_allocateFromManager_fail_noFunds() public {
        vm.startPrank(origamiMultisig);
        addThresholds(75e18, 20e18);

        uint256 amount = 100e18;
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.allocateFromManager(amount);
    }

    function test_allocateFromManager_success() public {
        vm.startPrank(origamiMultisig);
        addThresholds(75e18, 20e18);

        uint256 amount = 100e18;
        deal(address(asset), address(manager), amount);       
        manager.allocateFromManager(amount);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 100e18);
        assertEq(manager.availableToWithdraw(), 80e18);
        checkLatestAssetBalances(amount);
        checkCheckpointAssetBalances(amount);
    }

    function test_withdraw_failParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.withdraw(0, alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.withdraw(10, address(0));
    }

    function test_withdraw_noIdleStrategy_noBalance() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        uint256 balance = 20e18;

        deal(address(asset), address(manager), balance);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(asset), amount, balance));
        manager.withdraw(amount, alice);
    }

    function test_withdraw_noIdleStrategy_success() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        uint256 balance = 100e18;

        deal(address(asset), address(manager), balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, 0);
        manager.withdraw(amount, alice);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 0);
        checkLatestAssetBalances(0);
        checkCheckpointAssetBalances(0);
    }

    function test_withdraw_withIdleStrategy_noIdleStrategyBalance() public {
        vm.startPrank(origamiMultisig);
        addThresholds(200e18, 20e18);

        uint256 amount = 100e18;
        uint256 balance = 100e18;

        deal(address(asset), address(manager), balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, 0);
        manager.withdraw(amount, alice);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 0);
        checkLatestAssetBalances(0);
        checkCheckpointAssetBalances(0);
    }

    function test_withdraw_withIdleStrategy_partialIdleStrategyBalance_notEnough() public {
        vm.startPrank(origamiMultisig);
        // All allocated to idle
        addThresholds(0, 0);
        uint256 amount = 100e18;
        uint256 balance = 100e18; // only 80% available in mock idle strategy
        allocate(balance);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InsufficientBalance.selector, address(asset), amount, 80e18));
        manager.withdraw(amount, alice);
    }

    function test_withdraw_withIdleStrategy_allIdleStrategyBalance_zeroBuffer() public {
        vm.startPrank(origamiMultisig);
        // All allocated to idle
        addThresholds(0, 0);
        uint256 amount = 100e18;
        uint256 balance = 125e18; // only 80% available in mock idle strategy
        allocate(balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, amount);
        manager.withdraw(amount, alice);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 25e18);
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 20e18); // 80% of 25e18 remaining in idle strategy
        checkLatestAssetBalances(25e18);
        checkCheckpointAssetBalances(25e18);
    }

    function test_withdraw_withIdleStrategy_partialIdleStrategyBalance_zeroBuffer() public {
        vm.startPrank(origamiMultisig);
        addThresholds(25e18, 0);
        uint256 amount = 100e18;
        uint256 balance = 125e18; // only 80% available in mock idle strategy
        allocate(balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, 75e18);
        manager.withdraw(amount, alice);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 25e18);
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 20e18); // 80% of 25e18
        checkLatestAssetBalances(25e18);
        checkCheckpointAssetBalances(25e18);
    }

    function test_withdraw_withIdleStrategy_partialIdleStrategyBalance_withBuffer_hitMaxAvailable() public {
        vm.startPrank(origamiMultisig);
        addThresholds(25e18, 10e18);
        uint256 amount = 100e18;
        uint256 balance = 125e18; // only 80% available in mock idle strategy
        allocate(balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, 85e18);
        manager.withdraw(amount, alice);

        // 85e18 was withdrawn from idle, but only 80e18 available.
        // So 105e18 total balance in manager before alice withdrawal
        assertEq(asset.balanceOf(address(manager)), 5e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 20e18); // Still 20e18 in idle
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 21e18); // 5 + 80% of 20e18
        checkLatestAssetBalances(25e18);
        checkCheckpointAssetBalances(25e18);
    }

    function test_withdraw_withIdleStrategy_partialIdleStrategyBalance_withBuffer_overMaxAvailable() public {
        vm.startPrank(origamiMultisig);
        addThresholds(25e18, 10e18);
        uint256 amount = 100e18;
        uint256 balance = 200e18; // only 80% available in mock idle strategy
        allocate(balance);

        vm.expectEmit(address(manager));
        emit Withdrawn(alice, amount, 85e18);
        manager.withdraw(amount, alice);

        // 85e18 was withdrawn from idle, (and loads available).
        // Just the withdrawal buffer left in manager
        assertEq(asset.balanceOf(address(manager)), 10e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 90e18);
        assertEq(asset.balanceOf(alice), amount);
        assertEq(manager.availableToWithdraw(), 10e18+72e18);
        checkLatestAssetBalances(10e18 + 90e18);
        checkCheckpointAssetBalances(10e18 + 90e18);
    }

    function test_withdrawToManager_lessFunds() public {
        vm.startPrank(origamiMultisig);
        addThresholds(20e18, 25e18);
        allocate(50e18);

        {
            assertEq(asset.balanceOf(address(manager)), 20e18);
            assertEq(asset.balanceOf(address(origamiMultisig)), 0);
            assertEq(asset.balanceOf(address(idleStrategy)), 30e18);
            assertEq(manager.availableToWithdraw(), 44e18);
        }

        uint256 amountOut = manager.withdrawToManager(100e18);
        assertEq(amountOut, 24e18);
        
        {
            assertEq(asset.balanceOf(address(manager)), 44e18);
            assertEq(asset.balanceOf(address(origamiMultisig)), 0);
            assertEq(asset.balanceOf(address(idleStrategy)), 6e18);
            assertEq(manager.availableToWithdraw(), 48.8e18);
        }
    }

    function test_withdrawToManager_moreFunds() public {
        vm.startPrank(origamiMultisig);
        addThresholds(20e18, 25e18);
        allocate(50e18);

        {
            assertEq(asset.balanceOf(address(manager)), 20e18);
            assertEq(asset.balanceOf(address(origamiMultisig)), 0);
            assertEq(asset.balanceOf(address(idleStrategy)), 30e18);
            assertEq(manager.availableToWithdraw(), 44e18);
        }

        uint256 amountOut = manager.withdrawToManager(15e18);
        assertEq(amountOut, 15e18);
        
        {
            assertEq(asset.balanceOf(address(manager)), 35e18);
            assertEq(asset.balanceOf(address(origamiMultisig)), 0);
            assertEq(asset.balanceOf(address(idleStrategy)), 15e18);
            assertEq(manager.availableToWithdraw(), 47e18);
        }
    }

    function test_allocateAndWithdraw_equalThreshold() public {
        vm.startPrank(origamiMultisig);
        // 100% as available for this test
        idleStrategy.setAvailableSplit(10_000);
        addThresholds(25e18, 25e18);

        deal(address(asset), origamiMultisig, 100e18);
        asset.approve(address(manager), 100_000e18);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);

        // 25 is kept in the manager (depositThreshold)
        manager.allocate(100e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only pulled from the manager
        manager.withdraw(25e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 25e18);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only deposited into the manager
        allocate(25e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only pulled from the manager
        manager.withdraw(25e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 25e18);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);
    }

    function test_allocateAndWithdraw_smallerWithdrawalThreshold() public {
        vm.startPrank(origamiMultisig);
        // 100% as available for this test
        idleStrategy.setAvailableSplit(10_000);
        addThresholds(25e18, 20e18);

        deal(address(asset), origamiMultisig, 100e18);
        asset.approve(address(manager), 100_000e18);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);

        // 25 is kept in the manager (depositThreshold)
        manager.allocate(100e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only pulled from the manager
        manager.withdraw(23e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 23e18);
        assertEq(asset.balanceOf(address(manager)), 2e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only deposited into the manager
        allocate(23e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);

        // Only pulled from the manager
        manager.withdraw(23e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 23e18);
        assertEq(asset.balanceOf(address(manager)), 2e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 75e18);
    }

    function test_allocateAndWithdraw_fail_largerWithdrawalThreshold() public {
        vm.startPrank(origamiMultisig);
        addThresholds(20e18, 25e18);

        deal(address(asset), origamiMultisig, 100e18);
        asset.approve(address(manager), 100_000e18);

        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(asset.balanceOf(address(idleStrategy)), 0);

        // 20 is kept in the manager (depositThreshold)
        manager.allocate(100e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 20e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 80e18);

        // This is chruning smaller deposits into the underlying idle strategy
        // but in reality it's unlikely there'll be a single repeated
        // allocate() and withraw() in the range depositThreshold < x <= withdrawThreshold
        // 
        // If there is a withdrawal, it is a valid possibility that we will want to
        // withdraw a decent amount (more than we keep when there's a deposit)
        // At the end of the day, it's the user paying for this gas anyway.
        manager.withdraw(23e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 23e18);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 52e18);

        allocate(23e18);
        assertEq(asset.balanceOf(address(origamiMultisig)), 0);
        assertEq(asset.balanceOf(address(manager)), 20e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 80e18);

        manager.withdraw(23e18, origamiMultisig);
        assertEq(asset.balanceOf(address(origamiMultisig)), 23e18);
        assertEq(asset.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(idleStrategy)), 52e18);
    }
}