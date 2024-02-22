pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiAaveV3IdleStrategy } from "contracts/investments/lending/idleStrategy/OrigamiAaveV3IdleStrategy.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiAaveV3IdleStrategyTest is OrigamiTest {
    using SafeERC20 for IERC20;

    event Allocated(uint256 amount);
    event Withdrawn(uint256 amount, address indexed recipient);

    address public usdcToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public poolAddressProvider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    OrigamiAaveV3IdleStrategy public idleStrategy;

    function setUp() public {
        fork("mainnet", 17625800);
        vm.warp(1688537267); // The unix ts of block #17625800

        idleStrategy = new OrigamiAaveV3IdleStrategy(origamiMultisig, usdcToken, poolAddressProvider);
    }

    function maxBorrow() internal {
        uint256 supplyAmount = 50_000e18;
        IERC20 wstEth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        doMint(wstEth, bob, supplyAmount);

        vm.startPrank(bob);
        IPool lendingPool = IPool(IPoolAddressesProvider(poolAddressProvider).getPool());
        wstEth.forceApprove(address(lendingPool), supplyAmount);
        lendingPool.supply(address(wstEth), supplyAmount, bob, 0 /* no referralCode */);

        // Borrow all but 15k USDC
        uint256 idleUsdc = IERC20(usdcToken).balanceOf(address(idleStrategy.aToken()));
        lendingPool.borrow(usdcToken, idleUsdc - 15_000e6, 2, 0, bob);
    }

    function test_initialization() public {
        assertEq(address(idleStrategy.owner()), origamiMultisig);
        assertEq(address(idleStrategy.asset()), usdcToken);
        assertEq(address(idleStrategy.lendingPool()), 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
        assertEq(address(idleStrategy.aToken()), 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        assertEq(idleStrategy.availableToWithdraw(), 0);
        assertEq(idleStrategy.totalBalance(), 0);
    }

    function test_access_allocate() public {
        expectElevatedAccess();
        idleStrategy.allocate(100e6);
    }

    function test_access_withdraw() public {
        expectElevatedAccess();
        idleStrategy.withdraw(100e6, alice);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        idleStrategy.recoverToken(alice, alice, 100e18);
    }

    function test_fail_recoverToken() public {
        vm.startPrank(origamiMultisig);
        address aToken = address(idleStrategy.aToken());
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, aToken));
        idleStrategy.recoverToken(aToken, alice, 100e18);
    }

    function test_recoverToken() public {
        check_recoverToken(address(idleStrategy));
    }

    function test_allocate_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        idleStrategy.allocate(0);
    }

    function test_allocate_success() public {
        uint256 amount = 10_000e6;
        vm.startPrank(origamiMultisig);
        doMint(IERC20(usdcToken), origamiMultisig, amount);
        IERC20(usdcToken).approve(address(idleStrategy), amount);

        vm.expectEmit(address(idleStrategy));
        emit Allocated(amount);
        idleStrategy.allocate(amount);

        assertEq(IERC20(usdcToken).balanceOf(origamiMultisig), 0);
        assertEq(idleStrategy.aToken().balanceOf(address(idleStrategy)), amount);

        assertEq(idleStrategy.availableToWithdraw(), amount);
        assertEq(idleStrategy.totalBalance(), amount);
    }

    function allocate(uint256 amount) internal {
        vm.startPrank(origamiMultisig);
        doMint(IERC20(usdcToken), origamiMultisig, amount);
        IERC20(usdcToken).approve(address(idleStrategy), amount);
        idleStrategy.allocate(amount);

    }

    function test_withdraw_fail() public {
        uint256 amount = 10_000e6;
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        idleStrategy.withdraw(amount, bob);
    }

    function test_withdraw_success_all() public {
        uint256 amount = 10_000e6;
        allocate(amount);

        vm.expectEmit(address(idleStrategy));
        emit Withdrawn(amount, bob);
        idleStrategy.withdraw(amount, bob);

        assertEq(IERC20(usdcToken).balanceOf(origamiMultisig), 0);
        assertEq(idleStrategy.aToken().balanceOf(address(idleStrategy)), 0);
        assertEq(IERC20(usdcToken).balanceOf(bob), amount);

        assertEq(idleStrategy.availableToWithdraw(), 0);
        assertEq(idleStrategy.totalBalance(), 0);
    }

    function test_withdraw_success_less() public {
        uint256 amount = 10_000e6;
        allocate(amount);

        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(address(idleStrategy));
        emit Withdrawn(amount, bob);
        idleStrategy.withdraw(amount, bob);

        uint256 expectedBalance = 21.850510e6;
        assertEq(IERC20(usdcToken).balanceOf(origamiMultisig), 0);
        assertEq(idleStrategy.aToken().balanceOf(address(idleStrategy)), expectedBalance);
        assertEq(IERC20(usdcToken).balanceOf(bob), amount);

        assertEq(idleStrategy.availableToWithdraw(), expectedBalance);
        assertEq(idleStrategy.totalBalance(), expectedBalance);
    }

    function test_withdraw_success_more() public {
        uint256 amount = 10_000e6;
        allocate(amount);

        vm.warp(block.timestamp + 30 days);

        uint256 expectedTotal = amount + 21.850511e6;
        vm.expectEmit(address(idleStrategy));
        emit Withdrawn(expectedTotal, bob);
        idleStrategy.withdraw(amount * 2, bob);

        assertEq(IERC20(usdcToken).balanceOf(origamiMultisig), 0);
        assertEq(idleStrategy.aToken().balanceOf(address(idleStrategy)), 0);
        assertEq(IERC20(usdcToken).balanceOf(bob), expectedTotal);

        assertEq(idleStrategy.availableToWithdraw(), 0);
        assertEq(idleStrategy.totalBalance(), 0);
    }

    function test_withdraw_fail_nothingLeft() public {
        uint256 amount = 10_000e6;
        allocate(amount);

        vm.warp(block.timestamp + 30 days);

        idleStrategy.withdraw(amount * 2, bob);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        idleStrategy.withdraw(amount * 2, bob);
    }

    function test_available_maxUR() public {
        uint256 amount = 20_000e6;
        allocate(amount);

        vm.warp(block.timestamp + 30 days);

        // Someone else uses the entire pool except 15k
        maxBorrow();

        uint256 expectedTotal = amount + 43.697435e6;
        assertEq(idleStrategy.totalBalance(), expectedTotal);

        // The available is capped at what's remaining in the Aave pool - ie 15k
        assertEq(idleStrategy.availableToWithdraw(), 15_000e6);
    }
}
