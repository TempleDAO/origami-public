pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { OrigamiInfraredVaultManager } from "contracts/investments/infrared/OrigamiInfraredVaultManager.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";
import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiInfraredVaultManager } from "contracts/interfaces/investments/infrared/IOrigamiInfraredVaultManager.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { stdError } from "forge-std/StdError.sol";

contract OrigamiInfraredVaultManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    event AssetStaked(uint256 amount);
    event PerformanceFeesCollected(uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    IERC20 internal constant iBgtToken = IERC20(0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b);
    IERC20 internal constant wBeraToken = IERC20(0x6969696969696969696969696969696969696969);
    IERC20 internal constant honeyToken = IERC20(0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce);
    IInfraredVault internal iBgtVault = IInfraredVault(0x4EF0c533D065118907f68e6017467Eb05DBb2c8C);

    OrigamiDelegated4626Vault public vault;
    OrigamiInfraredVaultManager public manager;
    TokenPrices public tokenPrices;

    uint16 public constant PERF_FEE_FOR_CALLER = 0; // No incentivised flows
    uint16 public constant PERF_FEE_FOR_ORIGAMI = 100; // 1%

    address public swapper = makeAddr("swapper");

    uint256 public constant HONEY_REWARDS_AFTER_A_WEEK = 0.329556413320832e18;

    function setUp() public virtual {
        fork("berachain_mainnet", 980_084);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, "Origami iBGT Auto-Compounder", "oriBGT", iBgtToken, address(tokenPrices)
        );
        vm.label(address(vault), vault.symbol());

        manager = new OrigamiInfraredVaultManager(
            origamiMultisig,
            address(vault),
            address(iBgtToken),
            address(iBgtVault),
            feeCollector,
            swapper,
            PERF_FEE_FOR_ORIGAMI
        );
        vm.label(address(vault), "MANAGER");
        vm.label(swapper, "SWAPPER");
        vm.label(address(honeyToken), "HONEY_TOKEN");
        vm.label(address(iBgtToken), "iBGT_TOKEN");
        vm.label(address(wBeraToken), "wBERA_TOKEN");

        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();
    }

    function depositAll() internal returns (uint256) {
        vm.startPrank(address(vault));
        uint256 amountDeposited = manager.deposit(iBgtToken.balanceOf(address(manager)));
        vm.stopPrank();
        return amountDeposited;
    }
}

contract OrigamiInfraredVaultManagerTest_Admin is OrigamiInfraredVaultManagerTestBase {
    event PerformanceFeeSet(uint256 fee);
    event FeeCollectorSet(address indexed feeCollector);
    event SwapperSet(address indexed newSwapper);
    event FeeBpsSet(uint16 depositFeeBps, uint16 withdrawalFeeBps);
    event RewardsVestingDurationSet(uint48 durationInSeconds);

    function test_bad_constructor() public {
        // perf fees too high
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiInfraredVaultManager(
            origamiMultisig, address(vault), address(iBgtToken), address(iBgtVault), feeCollector, swapper, 10_001
        );

        // unexpected staking token or asset
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(honeyToken)));
        new OrigamiInfraredVaultManager(
            origamiMultisig, address(vault), address(honeyToken), address(iBgtVault), feeCollector, swapper, PERF_FEE_FOR_ORIGAMI
        );
    }

    function test_initialization() public view {
        assertEq(address(manager.owner()), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(address(manager.asset()), address(iBgtToken));
        assertEq(address(manager.rewardVault()), address(iBgtVault));
        assertEq(manager.depositFeeBps(), 0);
        assertEq(manager.MAX_WITHDRAWAL_FEE_BPS(), 330);
        assertEq(manager.feeCollector(), feeCollector);
        assertEq(manager.lastVestingCheckpoint(), 0);
        assertEq(manager.RESERVES_VESTING_DURATION(), 10 minutes);
        assertEq(manager.swapper(), swapper);
        assertEq(manager.withdrawalFeeBps(), 0);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, PERF_FEE_FOR_CALLER);
        assertEq(forOrigami, PERF_FEE_FOR_ORIGAMI);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.totalAssets(), 0);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), false);
        (uint256 vested, uint256 unvested, uint256 nextPeriodUnvested) = manager.vestingStatus();
        assertEq(vested, 0);
        assertEq(unvested, 0);
        assertEq(nextPeriodUnvested, 0);

        // Max approval set for deposits into the iBGT vault
        assertEq(iBgtToken.allowance(address(manager), address(iBgtVault)), type(uint256).max);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FeeCollectorSet(alice);
        manager.setFeeCollector(alice);
        assertEq(address(manager.feeCollector()), alice);
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
    }

    function test_setWithdrawalFee_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setWithdrawalFee(uint16(331));

        assertEq(manager.withdrawalFeeBps(), 0);
    }

    function test_setWithdrawalFee_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit FeeBpsSet(0, 330);
        manager.setWithdrawalFee(uint16(330));

        assertEq(manager.withdrawalFeeBps(), 330);
    }

    function test_setPerformanceFees_failTooHigh() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setPerformanceFees(101);
    }

    function test_setPerformanceFees_success() public {
        vm.startPrank(origamiMultisig);

        // It's emitted from the vault
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(99);
        manager.setPerformanceFees(99);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 0);
        assertEq(forOrigami, 99);
    }

    function test_setPerformanceFees_withHarvest() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        assertEq(depositAll(), 1000e18);
        skip(1 weeks);

        vm.startPrank(origamiMultisig);

        // an random EOA gets rewards on the manager's behalf from Infrared
        IMultiRewards(manager.rewardVault()).getRewardForUser(address(manager));
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(wBeraToken.balanceOf(address(swapper)), 0);
        assertEq(honeyToken.balanceOf(address(manager)), HONEY_REWARDS_AFTER_A_WEEK);

        // pretend iBGT was also distributed as rewards
        deal(address(iBgtToken), address(manager), 100e18);

        // reinvestment of pending rewards was triggered
        vm.expectEmit(address(manager));
        emit AssetStaked(99e18); // less 2% for origami

        // performance fee emitted from vault
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(10);

        manager.setPerformanceFees(10);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 0);
        assertEq(forOrigami, 10);

        // setting fees triggered reinvestment so HONEY was sent to the swapper and iBGT was clipped
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18); // 2% clipped
        assertEq(iBgtVault.balanceOf(address(manager)), 1099e18); // rest was staked

        assertEq(wBeraToken.balanceOf(address(swapper)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), HONEY_REWARDS_AFTER_A_WEEK); // all honey sent to swapper
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(iBgtToken)));
        manager.recoverToken(address(iBgtToken), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }
}

contract OrigamiInfraredVaultManagerTest_Access is OrigamiInfraredVaultManagerTestBase {
    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        manager.setFeeCollector(alice);
    }

    function test_setSwapper_access() public {
        expectElevatedAccess();
        manager.setSwapper(alice);
    }

    function test_setWithdrawalFee_access() public {
        expectElevatedAccess();
        manager.setWithdrawalFee(100);
    }

    function test_setPerformanceFees_access() public {
        expectElevatedAccess();
        manager.setPerformanceFees(1);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 100e18);
    }

    function test_deposit_access() public {
        expectElevatedAccess();
        manager.deposit(100);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.deposit(100);
    }

    function test_withdraw_access() public {
        expectElevatedAccess();
        manager.withdraw(100, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.withdraw(100, alice);
    }

    function test_setPauser_access() public {
        expectElevatedAccess();
        manager.setPauser(alice, true);
    }

    function test_setPaused_access() public {
        expectElevatedAccess();
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
    }
}

// @todo Donation by staking on behalf of the manager
// 

contract OrigamiInfraredVaultManagerTest_Staking is OrigamiInfraredVaultManagerTestBase {
    function test_stakeIBGT() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtVault.balanceOf(address(manager)), 1000e18);
    }

    function test_harvestRewards() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        skip(1 weeks);

        IInfraredVault.UserReward[] memory unclaimedRewards = manager.unclaimedRewards();
        assertEq(unclaimedRewards.length, 1);
        assertEq(unclaimedRewards[0].token, address(honeyToken));
        assertEq(unclaimedRewards[0].amount, HONEY_REWARDS_AFTER_A_WEEK);

        vm.startPrank(alice);

        // forking from this block, only HONEY rewards are distributed
        manager.harvestRewards(alice); // alice harvests altruistically but gets no caller fee

        // no iBGT or WBERA emissions
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(iBgtToken.balanceOf(feeCollector), 0);
        assertEq(iBgtToken.balanceOf(alice), 0);

        assertEq(wBeraToken.balanceOf(address(manager)), 0);
        assertEq(wBeraToken.balanceOf(address(swapper)), 0);
        assertEq(wBeraToken.balanceOf(address(feeCollector)), 0);
        assertEq(wBeraToken.balanceOf(alice), 0);

        // HONEY is sent to swapper
        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), HONEY_REWARDS_AFTER_A_WEEK); // all HONEY sent to swapper
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);

        // calling harvestRewards again immediately is a no-op
        manager.harvestRewards(alice);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(iBgtToken.balanceOf(feeCollector), 0);
        assertEq(iBgtToken.balanceOf(alice), 0);

        assertEq(wBeraToken.balanceOf(address(manager)), 0);
        assertEq(wBeraToken.balanceOf(address(swapper)), 0);
        assertEq(wBeraToken.balanceOf(address(feeCollector)), 0);
        assertEq(wBeraToken.balanceOf(alice), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), HONEY_REWARDS_AFTER_A_WEEK); // all HONEY sent to swapper
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);
    }

    function test_harvestRewards_withDonations() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        skip(1 weeks);

        // a donation of iBGT to the manager is received (or simulates rewards in iBGT being harvested)
        uint256 donationAmount = 100e18;
        deal(address(iBgtToken), address(manager), donationAmount);
        deal(address(honeyToken), address(manager), donationAmount);
        deal(address(wBeraToken), address(manager), donationAmount);

        vm.startPrank(alice);
        vm.expectEmit(address(manager));
        emit PerformanceFeesCollected(1e18);
        vm.expectEmit(address(manager));
        emit AssetStaked(99e18);
        manager.harvestRewards(alice);

        // donated iBGT (indistinguishable from iBGT rewards) are immediately reinvested after taking fees
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18); // 2% clipped
        assertEq(iBgtVault.balanceOf(address(manager)), 1099e18); // rest is immediately staked
        assertEq(iBgtToken.balanceOf(alice), 0);

        // full amount of reward tokens sent to the swapper, fees are collected later in iBGT
        assertEq(wBeraToken.balanceOf(address(manager)), 0);
        assertEq(wBeraToken.balanceOf(address(swapper)), donationAmount);
        assertEq(wBeraToken.balanceOf(address(feeCollector)), 0);
        assertEq(wBeraToken.balanceOf(alice), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), HONEY_REWARDS_AFTER_A_WEEK + donationAmount);
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);

        // calling harvestRewards again immediately is a noop
        manager.harvestRewards(alice);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(swapper)), 0);
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18);
        assertEq(iBgtVault.balanceOf(address(manager)), 1099e18);
        assertEq(iBgtToken.balanceOf(alice), 0);

        assertEq(wBeraToken.balanceOf(address(manager)), 0);
        assertEq(wBeraToken.balanceOf(address(swapper)), donationAmount);
        assertEq(wBeraToken.balanceOf(address(feeCollector)), 0);
        assertEq(wBeraToken.balanceOf(alice), 0);

        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), HONEY_REWARDS_AFTER_A_WEEK + donationAmount);
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);
    }
}

contract OrigamiInfraredVaultManagerTest_Deposit is OrigamiInfraredVaultManagerTestBase {
    event Staked(address indexed user, uint256 amount);

    function test_deposit_pausedOK() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        assertEq(manager.areDepositsPaused(), true);
        assertEq(manager.areWithdrawalsPaused(), false);

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(depositAll(), 0);
    }

    function test_deposit_successNothing() public {
        assertEq(depositAll(), 0);
    }

    function test_deposit_failTooMuch() public {
        vm.expectRevert("TRANSFER_FROM_FAILED");
        vm.prank(address(vault));
        manager.deposit(100e18);
    }

    function test_deposit_successWithDonations() public {
        // t0: simulate donations or rewards of asset 100e18
        deal(address(iBgtToken), address(manager), 100e18);
        vm.warp(block.timestamp + 1 hours);

        // t1: simulate the vault transferring 25e18 to the manager during a user deposit
        doMint(iBgtToken, address(manager), 25e18);

        vm.startPrank(address(vault));

        vm.expectEmit(address(manager));
        emit AssetStaked(25e18);
        vm.expectEmit(address(iBgtVault));
        emit Staked(address(manager), 25e18);
        vm.expectEmit(address(manager));
        emit AssetStaked(99e18);
        vm.expectEmit(address(iBgtVault));
        emit Staked(address(manager), 99e18); // donated amount is clipped then staked separately to the user deposit

        uint256 expectedTotalAssets = 99e18 + 25e18;

        uint256 depositedAmount = manager.deposit(25e18); // vault is expected to provide correct amount here
        assertEq(depositedAmount, 25e18);
        assertEq(iBgtVault.balanceOf(address(manager)), expectedTotalAssets);
        // donations/rewards were compounded as part of the users's deposit
        assertEq(iBgtToken.balanceOf(address(manager)), 0); 
        // 2% fee on the 100e18 donation only total assets doesn't change immediately
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18); 
        assertEq(manager.totalAssets(), 25e18);

        // total assets has increased after vesting period
        vm.warp(block.timestamp + 10 minutes);
        assertEq(manager.totalAssets(), expectedTotalAssets);
    }

    function test_deposit_successMaxIBGT() public {
        vm.startPrank(origamiMultisig);
        deal(address(iBgtToken), address(manager), 100e18);

        vm.expectEmit(address(manager));
        emit AssetStaked(100e18);
        vm.expectEmit(address(iBgtVault));
        emit Staked(address(manager), 100e18);

        uint256 depositedAmount = depositAll();
        assertEq(depositedAmount, 100e18);
        assertEq(iBgtVault.balanceOf(address(manager)), 100e18);
        assertEq(manager.stakedAssets(), 100e18);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 100e18);
    }

    function test_deposit_successZeroAmount() public {
        vm.startPrank(origamiMultisig);
        deal(address(iBgtToken), address(manager), 100e18);
        depositAll();

        // Check that harvestRewards still gets called        
        skip(1 weeks);
        uint256 expectedHoneyRewards = 0.033550281743035400e18;
        vm.expectEmit(address(honeyToken));
        emit Transfer(address(manager), address(swapper), expectedHoneyRewards);

        uint256 secondDepositAmount = depositAll();
        assertEq(secondDepositAmount, 0);
        assertEq(iBgtVault.balanceOf(address(manager)), 100e18);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 100e18);
        assertEq(honeyToken.balanceOf(swapper), expectedHoneyRewards);

        assertEq(iBgtToken.balanceOf(feeCollector), 0); 
        vm.warp(block.timestamp + 10 minutes);
        assertEq(manager.totalAssets(), 100e18);
    }
}

contract OrigamiInfraredVaultManagerTest_Withdraw is OrigamiInfraredVaultManagerTestBase {
    event AssetWithdrawn(uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    error ERC20InvalidReceiver(address);

    function test_withdraw_pausedOK() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), true);
        vm.startPrank(address(vault));

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(manager.withdraw(100, alice), 100);
    }

    function test_withdraw_successNothing() public {
        vm.startPrank(origamiMultisig);
        deal(address(iBgtToken), address(manager), 100e18);
        depositAll();

        vm.startPrank(address(vault));

        // Check that harvestRewards still gets called first
        skip(1 weeks);
        uint256 expectedHoneyRewards = 0.033550281743035400e18;
        vm.expectEmit(address(honeyToken));
        emit Transfer(address(manager), address(swapper), expectedHoneyRewards);

        assertEq(manager.withdraw(0, alice), 0);
    }

    function test_withdraw_failNotEnough() public {
        vm.startPrank(address(vault));

        // vault should not call with incorrect parameters but check that it reverts anyways
        vm.expectRevert(stdError.arithmeticError);
        assertEq(manager.withdraw(100e18, alice), 0);
    }

    function test_withdraw_success() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        vm.startPrank(address(vault));

        vm.expectEmit(address(iBgtVault));
        emit Withdrawn(address(manager), 10e18);

        vm.expectEmit(address(manager));
        emit AssetWithdrawn(10e18);

        assertEq(manager.withdraw(10e18, alice), 10e18);
        assertEq(manager.totalAssets(), 90e18);

        assertEq(iBgtVault.balanceOf(address(manager)), 90e18);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(alice)), 10e18);
    }

    function test_withdraw_successAllStaked() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        vm.startPrank(address(vault));
        assertEq(manager.withdraw(100e18, alice), 100e18);
        assertEq(manager.totalAssets(), 0);

        assertEq(iBgtVault.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(alice)), 100e18);
    }

    function test_withdraw_successSameReceiver() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);

        assertEq(iBgtVault.balanceOf(address(manager)), 50e18);
        assertEq(iBgtToken.balanceOf(address(manager)), 50e18);
    }

    function test_withdraw_failBadReceiver() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
        manager.withdraw(50e18, address(0));
    }

    function test_withdraw_successAllWithUnallocatedAssets() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), 100e18);

        // 2% of unallocated are reserved for origami
        assertEq(manager.totalAssets(), 100e18);
        assertEq(manager.unallocatedAssets(), 99e18);

        vm.startPrank(address(vault));
        // attempt to withdraw `totalStaked` amount
        // this produces a sensible result even though the vault would never call it (199e18 > totalAssets at the beginning of the drip window)
        assertEq(manager.withdraw(199e18, alice), 199e18);
        assertEq(iBgtVault.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(iBgtToken.balanceOf(address(alice)), 199e18);
        // fees were harvested along the way
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18);
    }

    function test_withdraw_successPartialWithUnallocatedAssets1() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), 100e18);

        vm.startPrank(address(vault));
        assertEq(manager.withdraw(150e18, alice), 150e18);

        // fees were collected prior to withdrawal
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18);
        // manager staked the rest of its assets
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        // staked = 100e18 + 100e18 - 1e18 (fee) - 150e18 (withdrawal)
        assertEq(iBgtVault.balanceOf(address(manager)), 49e18);
        // user received the rest
        assertEq(iBgtToken.balanceOf(address(alice)), 150e18);
    }

    function test_withdraw_successPartialWithUnallocatedAssets2() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), 100e18);

        // this time, the unallocated amount could have covered the withdrawal but it's reinvested
        // anyway to collect fees appropriately
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, alice), 50e18);

        // fees were collected prior to withdrawal
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18);
        // manager staked the rest of its assets
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        // staked = 100e18 + 100e18 - 1e18 (fee) - 50e18 (withdrawal)
        assertEq(iBgtVault.balanceOf(address(manager)), 149e18);
        // user received the rest
        assertEq(iBgtToken.balanceOf(address(alice)), 50e18);
    }

    function test_withdraw_failCannotWithdrawReservedFees() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), 100e18);

        vm.startPrank(address(vault));
        // vault wouldn't call this but check that it reverts
        vm.expectRevert(stdError.arithmeticError);
        manager.withdraw(200e18, alice);
    }
}

contract OrigamiInfraredVaultManagerTest_Reinvest is OrigamiInfraredVaultManagerTestBase {
    function test_harvestRewards() public {

    }

    function test_reinvest_noRewards() public {
        manager.reinvest();

        assertEq(manager.totalAssets(), 0);
        assertEq(manager.stakedAssets(), 0);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(honeyToken.balanceOf(swapper), 0);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.vestingReserves(), 0);
        assertEq(manager.lastVestingCheckpoint(), 0);
    }

    function test_reinvest_onlyIBGT_firstTime() public {
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();

        uint256 oldCheckpoint = vm.getBlockTimestamp();
        assertEq(manager.totalAssets(), 0);
        assertEq(manager.stakedAssets(), 99e18);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.lastVestingCheckpoint(), oldCheckpoint);

        skip(5 minutes); // half way through the duration
        assertEq(manager.totalAssets(), 99e18/2);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.lastVestingCheckpoint(), oldCheckpoint);
    }

    function test_reinvest_onlyIBGT_sameWindow() public {
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        uint256 oldCheckpoint = vm.getBlockTimestamp();

        skip(5 minutes); // half way through the duration

        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        assertEq(manager.totalAssets(), 99e18/2);
        assertEq(manager.stakedAssets(), 2*99e18);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.futureVestingReserves(), 99e18);
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.lastVestingCheckpoint(), oldCheckpoint);
    }

    function test_reinvest_onlyIBGT_onNewWindow() public {
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();

        skip(10 minutes);

        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        assertEq(manager.totalAssets(), 99e18);
        assertEq(manager.stakedAssets(), 2*99e18);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.lastVestingCheckpoint(), vm.getBlockTimestamp());
    }

    function test_reinvest_onlyIBGT_sameTime() public {
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        uint256 oldBlockTime = vm.getBlockTimestamp();
        skip(5 minutes); // half way through

        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        
        assertEq(manager.totalAssets(), 99e18/2);
        assertEq(manager.stakedAssets(), 3*99e18);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.futureVestingReserves(), 2*99e18);
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.lastVestingCheckpoint(), oldBlockTime);
    }

    function test_reinvest_onlyIBGT_delayedPendingStart() public {
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        uint256 oldBlockTime = vm.getBlockTimestamp();
        skip(5 minutes); // half way through

        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        
        {
            assertEq(manager.totalAssets(), 99e18/2);
            assertEq(manager.stakedAssets(), 3*99e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.futureVestingReserves(), 2*99e18);
            assertEq(manager.vestingReserves(), 99e18);
            assertEq(manager.lastVestingCheckpoint(), oldBlockTime);
        }

        // A decent chunk of time before called again. Future vesting reserves
        // dont start dripping until now
        skip(1 days);
        {
            assertEq(manager.totalAssets(), 99e18);
            assertEq(manager.stakedAssets(), 3*99e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.futureVestingReserves(), 2*99e18);
            assertEq(manager.vestingReserves(), 99e18);
            assertEq(manager.lastVestingCheckpoint(), oldBlockTime);
        }

        manager.reinvest();
        uint256 newBlockTime = vm.getBlockTimestamp();
        {
            assertEq(manager.totalAssets(), 99e18);
            assertEq(manager.stakedAssets(), 3*99e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.futureVestingReserves(), 0);
            assertEq(manager.vestingReserves(), 2*99e18);
            assertEq(manager.lastVestingCheckpoint(), newBlockTime);
        }

        skip(9 minutes); // 9/10ths through
        {
            assertEq(manager.totalAssets(), 99e18 + 2*99e18*9/10);
            assertEq(manager.stakedAssets(), 3*99e18);
            assertEq(manager.unallocatedAssets(), 0);
            assertEq(manager.futureVestingReserves(), 0);
            assertEq(manager.vestingReserves(), 2*99e18);
            assertEq(manager.lastVestingCheckpoint(), newBlockTime);
        }
    }

    function test_reinvest_onlyIBGT_1wei_withFees() public {
        deal(address(iBgtToken), address(manager), 1);
        vm.expectEmit(address(manager));
        emit PerformanceFeesCollected(1);
        manager.reinvest();

        // only fees
        assertEq(iBgtToken.balanceOf(feeCollector), 1);
        assertEq(manager.stakedAssets(), 0);
    }

    function test_reinvest_onlyIBGT_noFees() public {
        vm.startPrank(origamiMultisig);
        manager.setPerformanceFees(0);

        deal(address(iBgtToken), address(manager), 100e18);
        vm.expectEmit(address(manager));
        emit AssetStaked(100e18);
        manager.reinvest();

        // only fees
        assertEq(iBgtToken.balanceOf(feeCollector), 0);
        assertEq(manager.stakedAssets(), 100e18);
    }
}

contract OrigamiInfraredVaultManagerTest_Views is OrigamiInfraredVaultManagerTestBase {
    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiCompoundingVaultManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiDelegated4626VaultManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiInfraredVaultManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }

    function test_totalAssets_aboveZero() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(10 minutes);
        deal(address(iBgtToken), address(manager), 100e18);
        manager.reinvest();
        skip(5 minutes);
        assertEq(manager.totalAssets(), 100e18 + 99e18/2);
    }

    function test_totalAssets_flooredAtZero() public {
        deal(address(vault), alice, 100e18, true);
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(10 minutes);
        deal(address(iBgtToken), address(manager), 1_000e18);
        manager.reinvest();
        skip(1 minutes);
        assertEq(manager.totalAssets(), 100e18 + 990e18/10);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(vault.convertToAssets(1e18), 1.989999999999999999e18);
        assertEq(vault.convertToShares(1e18), 0.502512562814070351e18);
        assertEq(manager.stakedAssets(), 100e18 + 990e18);
        (
            uint256 currentPeriodVested,
            uint256 currentPeriodUnvested,
            uint256 futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 990e18/10);
        assertEq(currentPeriodUnvested, 990e18*9/10);
        assertEq(futurePeriodUnvested, 0);

        // Now a huge donation so the futureVestingReserves is large doesn't change things
        deal(address(iBgtToken), address(manager), 1_000_000e18);
        manager.reinvest();
        assertEq(manager.totalAssets(), 100e18 + 990e18/10);

        // This is not possible - but if there were a large withdraw (more than actual vesting)
        // the totalAssets gets floored to zero
        assertEq(manager.stakedAssets(), 991_090e18);
        vm.prank(address(vault));
        manager.withdraw(991_000e18, alice);
        assertEq(manager.totalAssets(), 0);
        assertEq(vault.convertToAssets(1e18), 0);
        assertEq(vault.convertToShares(1e18), 100000000000000000001e18);
        assertEq(manager.stakedAssets(), 90e18);
        (
            currentPeriodVested,
            currentPeriodUnvested,
            futurePeriodUnvested
        ) = manager.vestingStatus();
        assertEq(currentPeriodVested, 990e18/10);
        assertEq(currentPeriodUnvested, 990e18*9/10);
        assertEq(futurePeriodUnvested, 990_000e18);
    }

    function test_totalAssets_drippedRewardsNoDonation() public {
        deal(address(iBgtToken), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(manager.totalAssets(), 100e18, "totalAssets pre-donation");

        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), 100e18);
        // total assets not affected till reinvested
        assertEq(manager.totalAssets(), 100e18, "totalAssets post-donation");

        manager.reinvest();

        // at t0 nothing has changed
        assertEq(manager.totalAssets(), 100e18, "totalAssets t0");
        assertEq(manager.vestingReserves(), 99e18);
        assertEq(manager.futureVestingReserves(), 0);
        assertEq(manager.lastVestingCheckpoint(), vm.getBlockTimestamp());

        skip(5 minutes);
        // at t5 half of the assets have vested (minus the fee for origami)
        assertEq(manager.totalAssets(), 149.5e18, "totalAssets t5");

        skip(5 minutes);
        // at t10, 2% of assets are reserved for origami and rest is allocated to the vault
        assertEq(manager.totalAssets(), 199e18, "totalAssets t10");

        skip(5 minutes);
        // at t15 all pendingAssets have already vested and there should be no more increase in totalAssets
        assertEq(manager.totalAssets(), 199e18, "totalAssets t15");
    }

    function test_totalAssets_drippedRewardsWithDonationDuringWindow() public {
        uint256 initialDeposit = 100e18;
        deal(address(iBgtToken), address(manager), initialDeposit);
        assertEq(depositAll(), initialDeposit);
        assertEq(manager.totalAssets(), initialDeposit, "totalAssets pre-donation");

        uint256 rewards = 100e18;
        // simulate 100e18 rewards harvested
        deal(address(iBgtToken), address(manager), rewards);
        // total assets not affected till reinvested
        assertEq(manager.totalAssets(), initialDeposit, "totalAssets post-donation");

        manager.reinvest();
        // at t0 nothing has changed
        assertEq(manager.totalAssets(), initialDeposit, "totalAssets t0");
        // but all assets are staked (after taking fees)
        assertEq(iBgtVault.balanceOf(address(manager)), initialDeposit + rewards - 1e18, "staked t0");
        assertEq(manager.unallocatedAssets(), 0);

        skip(5 minutes);
        // at t5 half of the assets have vested (minus the fee for origami)
        uint256 totalAssetsT5 = manager.totalAssets();
        assertEq(totalAssetsT5, initialDeposit + (rewards - 1e18) / 2, "totalAssets t5, preDonation");
        assertEq(iBgtVault.balanceOf(address(manager)), initialDeposit + rewards - 1e18, "staked preDonation");

        // simulate 100e18 donation during the drip window
        // calling reinvest here during an active window should add the 100e18 to prePendingReserves
        uint256 donationAmount = 100e18;
        deal(address(iBgtToken), address(manager), donationAmount);
        uint256 finalAssetsStaked = initialDeposit + rewards - 1e18 + donationAmount - 1e18;
        manager.reinvest();
        assertEq(manager.totalAssets(), totalAssetsT5, "totalAssets t5, postDonation");
        // however, for farming efficiency, the asset should be immediately staked
        assertEq(iBgtVault.balanceOf(address(manager)), finalAssetsStaked, "staked postDonation");

        skip(5 minutes);
        // at t10, 2% of assets are reserved for origami and rest is allocated to the vault, ignoring the donation
        assertEq(manager.totalAssets(), initialDeposit + rewards - 1e18, "totalAssets t10");

        // at t10 we call reinvest, starting a drip window for the prePendingReserves of 100e18
        manager.reinvest();
        // no change in price immediately
        assertEq(manager.totalAssets(), initialDeposit + rewards - 1e18, "totalAssets t10");

        // we reach the final total after 10
        skip(10 minutes);
        assertEq(manager.totalAssets(), finalAssetsStaked, "totalAssets t20");
        assertEq(iBgtVault.balanceOf(address(manager)), finalAssetsStaked, "staked t20");
    }

    function test_getAllRewardTokens() public view {
        address[] memory rewardTokens = manager.getAllRewardTokens();
        assertEq(rewardTokens.length, 3);
        assertEq(rewardTokens[0], address(iBgtToken));
        assertEq(rewardTokens[1], address(wBeraToken));
        assertEq(rewardTokens[2], address(honeyToken));
    }

    function test_unclaimedRewards() public {
        IInfraredVault.UserReward[] memory rewards = manager.unclaimedRewards();
        assertEq(rewards.length, 0);

        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        skip(1 weeks);

        rewards = manager.unclaimedRewards();
        // only the HONEY rewards are dripping
        assertEq(rewards.length, 1);
        assertEq(rewards[0].token, address(honeyToken));
        assertEq(rewards[0].amount, HONEY_REWARDS_AFTER_A_WEEK);
    }
}

contract OrigamiInfraredVaultManagerTest_Swapper is OrigamiInfraredVaultManagerTestBase {
    OrigamiSwapperWithCallback public compoundingSwapper;
    DummyDexRouter public router;

    event Swap(address indexed tokenSold, uint256 amountSold, address indexed tokenBought, uint256 amountBought);

    function setUp() public override {
        super.setUp();

        router = new DummyDexRouter();
        compoundingSwapper = new OrigamiSwapperWithCallback(origamiMultisig);

        vm.startPrank(origamiMultisig);
        manager.setSwapper(address(compoundingSwapper));
        compoundingSwapper.whitelistRouter(address(router), true);
        vm.stopPrank();
        doMint(iBgtToken, address(router), 1_000_000e18);
    }

    function encode(
        uint256 sellAmount,
        uint256 requestedBuyAmount,
        uint256 buyTokenToReceiveAmount
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(IOrigamiSwapper.RouteDataWithCallback({
            minBuyAmount: requestedBuyAmount,
            router: address(router),
            receiver: address(manager),
            data: abi.encodeCall(
                DummyDexRouter.doExactSwap,
                (address(honeyToken), sellAmount, address(iBgtToken), buyTokenToReceiveAmount)
            )
        }));
    }

    function test_swapAfterHarvest_success() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        skip(1 weeks);

        vm.startPrank(alice);
        manager.harvestRewards(alice);

        // all HONEY sent to swapper
        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), 0); // unset
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);
        assertEq(honeyToken.balanceOf(address(compoundingSwapper)), HONEY_REWARDS_AFTER_A_WEEK);

        // output iBGT is transferred to the manager
        vm.expectEmit(address(iBgtToken));
        emit Transfer(address(compoundingSwapper), address(manager), 100e18);

        // the swap completed successfully
        vm.expectEmit(address(compoundingSwapper));
        emit Swap(address(honeyToken), HONEY_REWARDS_AFTER_A_WEEK, address(iBgtToken), 100e18);

        // the amount minus fees was staked
        vm.expectEmit(address(manager));
        emit AssetStaked(100e18 - 1e18);

        // swap the honey rewards for 100 iBGT
        vm.startPrank(origamiMultisig);
        compoundingSwapper.execute(
            honeyToken, HONEY_REWARDS_AFTER_A_WEEK, iBgtToken, encode(HONEY_REWARDS_AFTER_A_WEEK, 100e18, 100e18)
        );

        // 100 iBGT is transferred back to the manager, but then immediately staked
        assertEq(iBgtToken.balanceOf(address(manager)), 0);
        assertEq(manager.unallocatedAssets(), 0);
        // Staked - 2% as fees
        assertEq(manager.stakedAssets(), 1_000e18 + 99e18);
        assertEq(iBgtVault.balanceOf(address(manager)), 1000e18 + 99e18);

        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.totalAssets(), 1000e18); // not updated yet as the drip needs to happen first
        assertEq(iBgtToken.balanceOf(feeCollector), 1e18);

        // after the drip window, the totalAssets matches the staked amount
        skip(10 minutes);
        assertEq(manager.totalAssets(), 1_000e18 + 99e18);
    }

    function test_swapAfterHarvest_fail() public {
        deal(address(iBgtToken), address(manager), 1000e18);
        depositAll();

        skip(1 weeks);

        vm.startPrank(alice);
        manager.harvestRewards(alice);

        assertEq(honeyToken.balanceOf(address(compoundingSwapper)), HONEY_REWARDS_AFTER_A_WEEK);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 100e18, 99e18));
        compoundingSwapper.execute(
            honeyToken, HONEY_REWARDS_AFTER_A_WEEK, iBgtToken, encode(HONEY_REWARDS_AFTER_A_WEEK, 100e18, 99e18)
        );

        // the HONEY has not been converted or moved
        assertEq(honeyToken.balanceOf(address(manager)), 0);
        assertEq(honeyToken.balanceOf(address(swapper)), 0); // unset
        assertEq(honeyToken.balanceOf(address(compoundingSwapper)), HONEY_REWARDS_AFTER_A_WEEK);
        assertEq(honeyToken.balanceOf(address(feeCollector)), 0);
        assertEq(honeyToken.balanceOf(alice), 0);
    }
}
