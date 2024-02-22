pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiIdleStrategyTestBase } from "./OrigamiIdleStrategyTestBase.t.sol";

contract OrigamiAbstractIdleStrategyTest is OrigamiIdleStrategyTestBase {
    event Allocated(uint256 amount);
    event Withdrawn(uint256 amount, address indexed recipient);

    function test_dummy() public {
        assertEq(address(idleStrategy.owner()), origamiMultisig);
        assertEq(address(idleStrategy.asset()), address(asset));

        uint256 amount = 100e18;

        // Deal asset to Alice
        {
            deal(address(asset), alice, amount);
            vm.startPrank(alice);
            asset.approve(address(idleStrategy), amount);
        }

        // Allocate
        { 
            vm.expectEmit(address(idleStrategy));
            emit Allocated(amount);
            idleStrategy.allocate(amount);
            assertEq(asset.balanceOf(address(idleStrategy)), amount);
            assertEq(asset.balanceOf(alice), 0);
            assertEq(idleStrategy.availableToWithdraw(), 80e18);
            assertEq(idleStrategy.totalBalance(), amount);
        }

        // The same as totalBalance by default
        assertEq(idleStrategy.checkpointTotalBalance(), amount);

        // Request 25 and get 25
        {
            vm.expectEmit(address(idleStrategy));
            emit Withdrawn(25e18, bob);
            uint256 withdrawn = idleStrategy.withdraw(25e18, bob);
            assertEq(asset.balanceOf(address(idleStrategy)), 75e18);
            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(bob), 25e18);
            assertEq(withdrawn, 25e18);
            assertEq(idleStrategy.availableToWithdraw(), 60e18);
            assertEq(idleStrategy.totalBalance(), 75e18);
            assertEq(idleStrategy.checkpointTotalBalance(), 75e18);
        }

        // Request 130, but only get (100-25)*80% = 60
        // Then (100-25-60) = 15 left (12 available)
        {
            vm.expectEmit(address(idleStrategy));
            emit Withdrawn(60e18, bob);
            uint256 withdrawn = idleStrategy.withdraw(130e18, bob);
            assertEq(asset.balanceOf(address(idleStrategy)), 15e18);
            assertEq(asset.balanceOf(alice), 0);
            assertEq(asset.balanceOf(bob), 85e18);
            assertEq(withdrawn, 60e18);
            assertEq(idleStrategy.availableToWithdraw(), 12e18);
            assertEq(idleStrategy.totalBalance(), 15e18);
            assertEq(idleStrategy.checkpointTotalBalance(), 15e18);
        }
    }
}
