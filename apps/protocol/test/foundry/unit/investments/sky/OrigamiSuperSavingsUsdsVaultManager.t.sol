pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { MockSUsdsToken } from "contracts/test/external/maker/MockSUsdsToken.m.sol";
import { OrigamiSuperSavingsUsdsVault } from "contracts/investments/sky/OrigamiSuperSavingsUsdsVault.sol";
import { OrigamiSuperSavingsUsdsManager } from "contracts/investments/sky/OrigamiSuperSavingsUsdsManager.sol";
import { IOrigamiSuperSavingsUsdsManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSavingsUsdsManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { DummySkyStakingRewards } from "contracts/test/external/maker/DummySkyStakingRewards.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { stdError } from "forge-std/StdError.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract OrigamiSuperSavingsUsdsManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    DummyMintableToken public asset;
    MockSUsdsToken public sUSDS; 
    OrigamiSuperSavingsUsdsVault public vault;
    OrigamiSuperSavingsUsdsManager public manager;
    TokenPrices public tokenPrices;
    address public swapper = makeAddr("swapper");

    DummySkyStakingRewards public skyFarm1;
    DummyMintableToken public skyFarm1RewardsToken;
    DummySkyStakingRewards public skyFarm2;
    DummyMintableToken public skyFarm2RewardsToken;

    uint96 public constant SUSDS_INTEREST_RATE = 0.05e18;
    uint32 public constant SWITCH_FARM_COOLDOWN = 1 days;
    uint16 public constant PERF_FEE_FOR_CALLER = 100; // 1%
    uint16 public constant PERF_FEE_FOR_ORIGAMI = 400; // 4%

    uint256 public constant DEPOSIT_FEE = 0;
    uint256 public constant BOOTSTRAPPED_USDS_AMOUNT = 100_000_000e18;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        vm.warp(1726300000);

        asset = new DummyMintableToken(origamiMultisig, "USDS", "USDS", 18);
        sUSDS = new MockSUsdsToken(asset);
        sUSDS.setInterestRate(SUSDS_INTEREST_RATE);
        doMint(asset, address(sUSDS), BOOTSTRAPPED_USDS_AMOUNT);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiSuperSavingsUsdsVault(
            origamiMultisig, 
            "Origami sUSDS+s", 
            "sUSDS+s",
            asset,
            address(tokenPrices)
        );

        manager = new OrigamiSuperSavingsUsdsManager(
            origamiMultisig,
            address(vault),
            address(sUSDS),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );

        skyFarm1RewardsToken = new DummyMintableToken(origamiMultisig, "SKY", "SKY", 18);
        skyFarm1 = new DummySkyStakingRewards(address(skyFarm1RewardsToken), address(asset));
        deal(address(skyFarm1RewardsToken), address(skyFarm1), 10_000e18);
        skyFarm1.notifyRewardAmount(10_000e18);

        skyFarm2RewardsToken = new DummyMintableToken(origamiMultisig, "SUBDAO1", "SUBDAO1", 18);
        skyFarm2 = new DummySkyStakingRewards(address(skyFarm2RewardsToken), address(asset));
        deal(address(skyFarm2RewardsToken), address(skyFarm2), 3_000e18);
        skyFarm2.notifyRewardAmount(3_000e18);
        
        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager));
        vm.stopPrank();
    }

    function setupAndSwitchFarm() internal {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
    }

    function depositAll() internal returns (uint256) {
        return manager.deposit(type(uint256).max);
    }

    function allFarmDetails() internal view returns (IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory details) {
        uint256 length = manager.maxFarmIndex() + 1;
        uint32[] memory farmIndexes = new uint32[](length);
        for (uint32 i; i < length; ++i) {
            farmIndexes[i] = i;
        }

        return manager.farmDetails(farmIndexes);
    }
}

contract OrigamiSuperSavingsUsdsManagerTestAdmin is OrigamiSuperSavingsUsdsManagerTestBase {
    event PerformanceFeeSet(uint256 fee);
    event FeeCollectorSet(address indexed feeCollector);
    event SwitchFarmCooldownSet(uint32 cooldown);
    event SwapperSet(address indexed newSwapper);
    event FarmReferralCodeSet(uint32 indexed farmIndex, uint16 referralCode);

    event FarmAdded(
        uint32 indexed farmIndex,
        address indexed stakingAddress,
        address indexed rewardsToken,
        uint16 referralCode
    );

    event FarmRemoved(
        uint32 indexed farmIndex,
        address indexed stakingAddress,
        address indexed rewardsToken
    );

    event ClaimedReward(
        uint32 indexed farmIndex, 
        address indexed rewardsToken, 
        uint256 amountForCaller, 
        uint256 amountForOrigami, 
        uint256 amountForVault
    );

    function test_bad_constructor() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiSuperSavingsUsdsManager(
            origamiMultisig,
            address(vault),
            address(sUSDS),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            9_000,
            1_001
        );
    }

    function test_initialization() public {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(manager.asset(), address(asset));
        assertEq(address(manager.USDS()), address(asset));
        assertEq(address(manager.sUSDS()), address(sUSDS));
        assertEq(manager.totalAssets(), 0);
        assertEq(manager.maxFarmIndex(), 0);
        assertEq(manager.currentFarmIndex(), 0);
        assertEq(manager.switchFarmCooldown(), SWITCH_FARM_COOLDOWN);
        assertEq(manager.lastSwitchTime(), 1726300000);
        assertEq(manager.swapper(), swapper);
        assertEq(manager.feeCollector(), feeCollector);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 100);
        assertEq(forOrigami, 400);

        // Not setup by default
        IOrigamiSuperSavingsUsdsManager.Farm memory farm = manager.getFarm(0);
        assertEq(address(farm.staking), address(0));
        assertEq(address(farm.rewardsToken), address(0));
        assertEq(farm.referral, 0);
        assertEq(manager.sUsdsReferral(), 0);

        // Max approval set for sUSDS
        assertEq(asset.allowance(address(manager), address(sUSDS)), type(uint256).max);
    }

    function test_setPerformanceFees_failIncreasing() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setPerformanceFees(101, 400); // Can't increase total
    }

    function test_setPerformanceFees_success() public {
        vm.startPrank(origamiMultisig);

        // It's emitted from the vault
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(500);
        manager.setPerformanceFees(101, 399);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 101);
        assertEq(forOrigami, 399);
        
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(301);
        manager.setPerformanceFees(101, 200);
        (forCaller, forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 101);
        assertEq(forOrigami, 200);
    }

    function test_setPerformanceFees_withHarvest() public {
        setupAndSwitchFarm();

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(skyFarm1RewardsToken), 
            14.285714285714285376e18, 
            57.142857142857141504e18, 
            1357.142857142857110720e18
        );

        // It's emitted from the vault
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(500);
        manager.setPerformanceFees(101, 399);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 101);
        assertEq(forOrigami, 399);
        
        vm.expectEmit(address(vault));
        emit PerformanceFeeSet(301);
        manager.setPerformanceFees(101, 200);
        (forCaller, forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 101);
        assertEq(forOrigami, 200);

        // Both incentives go to the feeCollector
        assertEq(skyFarm1RewardsToken.balanceOf(feeCollector), 14.285714285714285376e18 + 57.142857142857141504e18);
        assertEq(skyFarm1RewardsToken.balanceOf(origamiMultisig), 0);
        assertEq(skyFarm1RewardsToken.balanceOf(swapper), 1357.142857142857110720e18);
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

    function test_setSwitchFarmCooldown_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit SwitchFarmCooldownSet(123);
        manager.setSwitchFarmCooldown(123);
        assertEq(manager.switchFarmCooldown(), 123);
    }

    function test_addFarm_failMaxFarms() public {
        vm.startPrank(origamiMultisig);
        for (uint256 i; i < 100; ++i) {
            DummySkyStakingRewards farm = new DummySkyStakingRewards(address(skyFarm1RewardsToken), address(asset));
            manager.addFarm(address(farm), uint16(i));
        }

        assertGt(uint160(address(manager.getFarm(100).staking)), 0);
        assertEq(uint160(address(manager.getFarm(101).staking)), 0);

        // Last one will fail
        {
            DummySkyStakingRewards farm = new DummySkyStakingRewards(address(skyFarm1RewardsToken), address(asset));
            vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.MaxFarms.selector));
            manager.addFarm(address(farm), 100);
        }
    }

    function test_addFarm_failNotUnique() public {
        vm.startPrank(origamiMultisig);
        DummySkyStakingRewards farm;
        for (uint256 i; i < 55; ++i) {
            farm = new DummySkyStakingRewards(address(skyFarm1RewardsToken), address(asset));
            manager.addFarm(address(farm), uint16(i));
        }

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmExistsAlready.selector, address(farm)));
        manager.addFarm(address(farm), 100);
    }

    function test_addFarm_failZeroAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 1));
        manager.addFarm(address(0), 0);
    }

    function test_addFarm_failWrongFarmToken() public {
        DummySkyStakingRewards badFarm = new DummySkyStakingRewards(address(skyFarm1RewardsToken), address(skyFarm2RewardsToken));

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 1));
        manager.addFarm(address(badFarm), 0);
    }

    function test_addFarm_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FarmAdded(1, address(skyFarm1), address(skyFarm1RewardsToken), 123);

        // Index starts at 1
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        // Index 0 is empty
        {
            IOrigamiSuperSavingsUsdsManager.Farm memory farm = manager.getFarm(0);
            assertEq(address(farm.staking), address(0));
            assertEq(address(farm.rewardsToken), address(0));
            assertEq(farm.referral, 0);
        }

        // Index 1 has this new farm
        {
            IOrigamiSuperSavingsUsdsManager.Farm memory farm = manager.getFarm(1);
            assertEq(address(farm.staking), address(skyFarm1));
            assertEq(address(farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(farm.referral, 123);
        }

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);

        // Index 0 has the sUSDS
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);

            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }

        // Index 1 has this new farm
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];

            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);

            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.maxFarmIndex(), 1); // new farm
        assertEq(manager.currentFarmIndex(), 0); // hasn't switched
    }

    function test_removeFarm_failures() public {
        vm.startPrank(origamiMultisig);

        // Adding the same farm to a different slot 
        manager.addFarm(address(skyFarm1), 1);
        manager.addFarm(address(skyFarm2), 2);

        assertEq(manager.maxFarmIndex(), 2); // new farm
        assertEq(manager.currentFarmIndex(), 0); // hasn't switched

        // Can't remove farm zero
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmStillInUse.selector, 0));
        manager.removeFarm(0);
        
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(2);
        assertEq(manager.currentFarmIndex(), 2);

        // Still can't remove farm zero
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 0));
        manager.removeFarm(0);

        // Still can't remove farm 2, it's in use
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmStillInUse.selector, 2));
        manager.removeFarm(2);

        // Stake (into 2)
        {
            deal(address(asset), address(manager), 100e18);
            depositAll();
        }

        // Also prank staking into 1
        {
            vm.startPrank(address(manager));
            asset.approve(address(skyFarm1), 100e18);
            deal(address(asset), address(manager), 100e18);
            skyFarm1.stake(100e18);
        }

        // Can't remove from 1 either, even though it's not the current farm.
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmStillInUse.selector, 1));
        manager.removeFarm(1);

        // Switch back to the sUSDS which will unstake from farm 2
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(0);

        // Still can't remove as there's an earned balance of rewards to claim first.
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmStillInUse.selector, 2));
        manager.removeFarm(2);

        uint32[] memory farmIndexes = new uint32[](2);
        farmIndexes[0] = 1;
        farmIndexes[1] = 2;
        manager.claimFarmRewards(farmIndexes, origamiMultisig);

        manager.removeFarm(2);

        // Farm 1 still had ghost stake
        // Can switch to it then away from it and claim those rewards, then remove.
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.FarmStillInUse.selector, 1));
        manager.removeFarm(1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(0);
        farmIndexes = new uint32[](1);
        farmIndexes[0] = 1;
        manager.claimFarmRewards(farmIndexes, origamiMultisig);
        manager.removeFarm(1);
    }

    function test_removeFarm_success() public {
        vm.startPrank(origamiMultisig);

        // Adding the same farm to a different slot 
        manager.addFarm(address(skyFarm1), 1);
        manager.addFarm(address(skyFarm2), 2);

        assertEq(asset.allowance(address(manager), address(skyFarm1)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);

        vm.expectEmit(address(manager));
        emit FarmRemoved(2, address(skyFarm2), address(skyFarm2RewardsToken));
        manager.removeFarm(2);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);

        // Farm 1 is still there
        IOrigamiSuperSavingsUsdsManager.Farm memory farm = manager.getFarm(1);
        assertEq(address(farm.staking), address(skyFarm1));
        assertEq(address(farm.rewardsToken), address(skyFarm1RewardsToken));
        assertEq(farm.referral, 1);

        // Farm 2 is removed
        farm = manager.getFarm(2);
        assertEq(address(farm.staking), address(0));
        assertEq(address(farm.rewardsToken), address(0));
        assertEq(farm.referral, 0);

        assertEq(manager.maxFarmIndex(), 2);
    }

    function test_setFarmReferralCode_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 1));
        manager.setFarmReferralCode(1, 1);
    }

    function test_setFarmReferralCode_sUsdsSuccess() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FarmReferralCodeSet(0, 123);
        manager.setFarmReferralCode(0, 123);
        assertEq(manager.sUsdsReferral(), 123);
    }
    
    function test_setFarmReferralCode_farmSuccess() public {
        vm.startPrank(origamiMultisig);
        manager.addFarm(address(skyFarm1), 1);
        vm.expectEmit(address(manager));
        emit FarmReferralCodeSet(1, 123);
        manager.setFarmReferralCode(1, 123);
        
        IOrigamiSuperSavingsUsdsManager.Farm memory farm = manager.getFarm(1);
        assertEq(address(farm.staking), address(skyFarm1));
        assertEq(address(farm.rewardsToken), address(skyFarm1RewardsToken));
        assertEq(farm.referral, 123);
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(asset)));
        manager.recoverToken(address(asset), alice, 100e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(sUSDS)));
        manager.recoverToken(address(sUSDS), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }

}

contract OrigamiSuperSavingsUsdsManagerTestAccess is OrigamiSuperSavingsUsdsManagerTestBase {
    function test_setPerformanceFees_access() public {
        expectElevatedAccess();
        manager.setPerformanceFees(1, 1);
    }

    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        manager.setFeeCollector(alice);
    }

    function test_setSwapper_access() public {
        expectElevatedAccess();
        manager.setSwapper(alice);
    }

    function test_setSwitchFarmCooldown_access() public {
        expectElevatedAccess();
        manager.setSwitchFarmCooldown(123);
    }

    function test_addFarm_access() public {
        expectElevatedAccess();
        manager.addFarm(alice, 123);
    }

    function test_removeFarm_access() public {
        expectElevatedAccess();
        manager.removeFarm(1);
    }

    function test_setFarmReferralCode_access() public {
        expectElevatedAccess();
        manager.setFarmReferralCode(1, 123);
    }

    function test_switchFarms_access() public {
        expectElevatedAccess();
        manager.switchFarms(1);
    }

    // NB: Anyone can call deposit, but only the vault can withdraw
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

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 100e18);
    }
}

contract OrigamiSuperSavingsUsdsManagerTestDeposit is OrigamiSuperSavingsUsdsManagerTestBase {
    event Staked(address indexed user, uint256 amount);
    event Referral(uint16 indexed referral, address indexed user, uint256 amount);
    event Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares);

    function test_deposit_failPaused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        assertEq(manager.areDepositsPaused(), true);
        assertEq(manager.areWithdrawalsPaused(), false);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        depositAll();
    }

    function test_deposit_successNothing() public {
        assertEq(depositAll(), 0);
    }

    function test_deposit_fail_tooMuch() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.deposit(100e18);
    }

    function test_deposit_successLimitedSUsds() public {
        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), 100e18);
        vm.expectEmit(address(sUSDS));
        emit Deposit(address(manager), address(manager), 25e18, 25e18);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(sUSDS.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(manager)), 75e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
        
        assertEq(address(details.farm.staking), address(0));
        assertEq(address(details.farm.rewardsToken), address(0));
        assertEq(details.farm.referral, 0);
        assertEq(details.stakedBalance, 25.003424657534246575e18);
        assertEq(details.totalSupply, 25.003424657534246575e18);
        assertEq(details.rewardRate, 0.05e18);
        assertEq(details.unclaimedRewards, 0);
    }

    function test_deposit_successSUsdsReferral() public {
        vm.startPrank(origamiMultisig);
        manager.setFarmReferralCode(0, 123);
        deal(address(asset), address(manager), 100e18);
        vm.expectEmit(address(sUSDS));
        emit Deposit(address(manager), address(manager), 25e18, 25e18);
        vm.expectEmit(address(sUSDS));
        emit Referral(123, address(manager), 25e18, 25e18);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(sUSDS.balanceOf(address(manager)), 25e18);
        assertEq(asset.balanceOf(address(manager)), 75e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
        
        assertEq(address(details.farm.staking), address(0));
        assertEq(address(details.farm.rewardsToken), address(0));
        assertEq(details.farm.referral, 0);
        assertEq(details.stakedBalance, 25.003424657534246575e18);
        assertEq(details.totalSupply, 25.003424657534246575e18);
        assertEq(details.rewardRate, 0.05e18);
        assertEq(details.unclaimedRewards, 0);
    }

    function test_deposit_successMaxSUsds() public {
        vm.startPrank(origamiMultisig);
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(sUSDS.balanceOf(address(manager)), 100e18);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100.013698630136986301e18);
            assertEq(details.totalSupply, 100.013698630136986301e18);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }
    }

    function test_deposit_successZeroAmount() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
        assertEq(depositAll(), 0);
    }

    function test_deposit_successSkyFarm1_limited() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 0), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(asset), address(manager), 100e18);

        vm.expectEmit(address(skyFarm1));
        emit Staked(address(manager), 25e18);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(asset.balanceOf(address(manager)), 75e18);
        assertEq(sUSDS.balanceOf(address(manager)), 0);
        assertEq(skyFarm1.balanceOf(address(manager)), 25e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 25e18);
            assertEq(details.totalSupply, 25e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }
    }

    function test_deposit_successSkyFarm1_noReferral() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 0), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(asset), address(manager), 100e18);

        vm.expectEmit(address(skyFarm1));
        emit Staked(address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(asset.balanceOf(address(manager)), 0);
        assertEq(sUSDS.balanceOf(address(manager)), 0);
        assertEq(skyFarm1.balanceOf(address(manager)), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }
    }

    function test_deposit_successSkyFarm1_withReferral() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(asset), address(manager), 100e18);

        vm.expectEmit(address(skyFarm1));
        emit Staked(address(manager), 100e18);
        vm.expectEmit(address(skyFarm1));
        emit Referral(123, address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        assertEq(sUSDS.balanceOf(address(manager)), 0);
        assertEq(skyFarm1.balanceOf(address(manager)), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }
    }
}

contract OrigamiSuperSavingsUsdsManagerTestWithdraw is OrigamiSuperSavingsUsdsManagerTestBase {
    function test_withdraw_failPaused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), true);
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        manager.withdraw(100, alice);
    }

    function test_withdraw_sUSDS_successNothing() public {
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(0, alice), 0);
    }

    function test_withdraw_sUSDS_failNotEnough() public {
        vm.startPrank(address(vault));
        vm.expectRevert("ERC4626: withdraw more than max");
        assertEq(manager.withdraw(100e18, alice), 0);
    }

    function test_withdraw_sUSDS_success() public {
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(manager.totalAssets(), alice), 100.013698630136986301e18);

        assertEq(asset.balanceOf(alice), 100.013698630136986301e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }
        
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_sUSDS_maxSuccess() public {
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(type(uint256).max, alice), 100.013698630136986301e18);

        assertEq(asset.balanceOf(alice), 100.013698630136986301e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_sUSDS_successSameReceiver() public {
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);

        assertEq(asset.balanceOf(address(manager)), 50e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 50.020549821730155751e18);
            assertEq(details.totalSupply, 50.020549821730155751e18);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }
    }

    function test_withdraw_farm_failNothing() public {
        setupAndSwitchFarm();

        vm.startPrank(address(vault));
        vm.expectRevert("Cannot withdraw 0");
        manager.withdraw(0, alice);
    }

    function test_withdraw_farm_failNotEnough() public {
        setupAndSwitchFarm();

        vm.startPrank(address(vault));
        vm.expectRevert(stdError.arithmeticError); // underflow from not enough balance
        assertEq(manager.withdraw(100e18, alice), 0);
    }

    function test_withdraw_farm_success() public {
        setupAndSwitchFarm();
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(manager.totalAssets(), alice), 100e18);

        assertEq(asset.balanceOf(alice), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_farm_maxSuccess() public {
        setupAndSwitchFarm();
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(type(uint256).max, alice), 100e18);

        assertEq(asset.balanceOf(alice), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_farm_successSameReceiver() public {
        setupAndSwitchFarm();
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);

        assertEq(asset.balanceOf(address(manager)), 50e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 50e18);
            assertEq(details.totalSupply, 50e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 2857.142857142857075200e18);
        }
        assertEq(manager.totalAssets(), 100e18);
    }
}

contract OrigamiSuperSavingsUsdsManagerTestSwitch is OrigamiSuperSavingsUsdsManagerTestBase {
    event SwitchedFarms(
        uint32 indexed oldFarmIndex, 
        uint32 indexed newFarmIndex, 
        uint256 amountWithdrawn, 
        uint256 amountDeposited
    );

    function test_switchFarms_failBeforeCooldown() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN-1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.BeforeCooldownEnd.selector));
        manager.switchFarms(1);
    }

    function test_switchFarms_failSwitchToTheSame() public {
        vm.startPrank(origamiMultisig);
        skip(SWITCH_FARM_COOLDOWN);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 0));
        manager.switchFarms(0);
    }

    function test_switchFarms_failNotSetup() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 2));
        manager.switchFarms(2);
    }

    function test_switchFarms_sUsdsToFarm_noBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 0, 0);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 0);
        assertEq(deposited, 0);
    }

    function test_switchFarms_sUsdsToFarm_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        assertEq(asset.allowance(address(manager), address(sUSDS)), type(uint256).max);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 100.013698630136986301e18, 100.013698630136986301e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 100.013698630136986301e18);
        assertEq(deposited, 100.013698630136986301e18);
        assertEq(manager.totalAssets(), 100.013698630136986301e18);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 100.013698630136986301e18);
            assertEq(details.totalSupply, 100.013698630136986301e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 1);
        assertEq(manager.lastSwitchTime(), block.timestamp);

        assertEq(asset.allowance(address(manager), address(sUSDS)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), type(uint256).max);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);
    }

    function test_switchFarms_sUsdsToFarm_withDonation() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        // Slide in another donation
        deal(address(asset), address(manager), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 100.013698630136986301e18, 200.013698630136986301e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 100.013698630136986301e18);
        assertEq(deposited, 200.013698630136986301e18);
        assertEq(manager.totalAssets(), 200.013698630136986301e18);


        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 200.013698630136986301e18);
            assertEq(details.totalSupply, 200.013698630136986301e18);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 1);
        assertEq(manager.lastSwitchTime(), block.timestamp);
    }

    function test_switchFarms_FarmToFarm_noBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
        
        skip(SWITCH_FARM_COOLDOWN);
        vm.expectRevert("Cannot withdraw 0");
        manager.switchFarms(2);
    }

    function test_switchFarms_FarmToFarm_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        assertEq(asset.allowance(address(manager), address(sUSDS)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), type(uint256).max);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(1, 2, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(2);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 100e18);


        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 3);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[2];
            assertEq(address(details.farm.staking), address(skyFarm2));
            assertEq(address(details.farm.rewardsToken), address(skyFarm2RewardsToken));
            assertEq(details.farm.referral, 456);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.004960317460317460e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 2);
        assertEq(manager.lastSwitchTime(), block.timestamp);

        assertEq(asset.allowance(address(manager), address(sUSDS)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), type(uint256).max);
    }

    function test_switchFarms_FarmToSUsds_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        assertEq(asset.allowance(address(manager), address(sUSDS)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), type(uint256).max);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(1, 0, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(0);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 100e18);

        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 3);
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(skyFarm1));
            assertEq(address(details.farm.rewardsToken), address(skyFarm1RewardsToken));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.016534391534391534e18);
            assertEq(details.unclaimedRewards, 1428.571428571428537600e18);
        }

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 0);
        assertEq(manager.lastSwitchTime(), block.timestamp);

        assertEq(asset.allowance(address(manager), address(sUSDS)), type(uint256).max);
        assertEq(asset.allowance(address(manager), address(skyFarm1)), 0);
        assertEq(asset.allowance(address(manager), address(skyFarm2)), 0);
    }
}

contract OrigamiSuperSavingsUsdsManagerTestRewards is OrigamiSuperSavingsUsdsManagerTestBase {
    event ClaimedReward(
        uint32 indexed farmIndex, 
        address indexed rewardsToken, 
        uint256 amountForCaller, 
        uint256 amountForOrigami, 
        uint256 amountForVault
    );

    function test_claimFarmRewards_successNoIndexes() public {
        manager.claimFarmRewards(new uint32[](0), origamiMultisig);
    }

    function test_claimFarmRewards_failUsdsIndex() public {
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSavingsUsdsManager.InvalidFarm.selector, 0));
        manager.claimFarmRewards(indexes, origamiMultisig);
    }

    function test_claimFarmRewards_successNoBalance() public {
        setupAndSwitchFarm();

        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 1;
        manager.claimFarmRewards(indexes, origamiMultisig);
    }

    function test_claimFarmRewards_successWithBalance() public {
        setupAndSwitchFarm();

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 1;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(skyFarm1RewardsToken), 
            14.285714285714285376e18, 
            57.142857142857141504e18, 
            1357.142857142857110720e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(skyFarm1RewardsToken.balanceOf(alice), 14.285714285714285376e18);
        assertEq(skyFarm1RewardsToken.balanceOf(feeCollector), 57.142857142857141504e18);
        assertEq(skyFarm1RewardsToken.balanceOf(swapper), 1357.142857142857110720e18);
    }

    function test_claimFarmRewards_successDifferentRecipient() public {
        setupAndSwitchFarm();

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 1;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(skyFarm1RewardsToken), 
            14.285714285714285376e18, 
            57.142857142857141504e18, 
            1357.142857142857110720e18
        );
        manager.claimFarmRewards(indexes, bob);

        assertEq(skyFarm1RewardsToken.balanceOf(alice), 0);
        assertEq(skyFarm1RewardsToken.balanceOf(bob), 14.285714285714285376e18);
        assertEq(skyFarm1RewardsToken.balanceOf(feeCollector), 57.142857142857141504e18);
        assertEq(skyFarm1RewardsToken.balanceOf(swapper), 1357.142857142857110720e18);
    }

    function test_claimFarmRewards_successMultiple() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(origamiMultisig);
        manager.switchFarms(2);
        skip(SWITCH_FARM_COOLDOWN);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(skyFarm1RewardsToken), 
            14.285714285714285376e18, 
            57.142857142857141504e18, 
            1357.142857142857110720e18
        );
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            2, 
            address(skyFarm2RewardsToken), 
            4.285714285714285440e18, 
            17.142857142857141760e18, 
            407.142857142857116800e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(skyFarm1RewardsToken.balanceOf(alice), 14.285714285714285376e18);
        assertEq(skyFarm1RewardsToken.balanceOf(feeCollector), 57.142857142857141504e18);
        assertEq(skyFarm1RewardsToken.balanceOf(swapper), 1357.142857142857110720e18);
        assertEq(skyFarm2RewardsToken.balanceOf(alice), 4.285714285714285440e18);
        assertEq(skyFarm2RewardsToken.balanceOf(feeCollector), 17.142857142857141760e18);
        assertEq(skyFarm2RewardsToken.balanceOf(swapper), 407.142857142857116800e18);
    }

    function test_claimFarmRewards_withDonation() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(2);
        skip(SWITCH_FARM_COOLDOWN);

        deal(address(skyFarm1RewardsToken), address(manager), 250e18);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(skyFarm1RewardsToken), 
            16.785714285714285376e18, 
            67.142857142857141504e18, 
            1594.642857142857110720e18
        );
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            2, 
            address(skyFarm2RewardsToken), 
            4.285714285714285440e18, 
            17.142857142857141760e18, 
            407.142857142857116800e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(skyFarm1RewardsToken.balanceOf(alice), 16.785714285714285376e18);
        assertEq(skyFarm1RewardsToken.balanceOf(feeCollector), 67.142857142857141504e18);
        assertEq(skyFarm1RewardsToken.balanceOf(swapper), 1594.642857142857110720e18);
        assertEq(skyFarm2RewardsToken.balanceOf(alice), 4.285714285714285440e18);
        assertEq(skyFarm2RewardsToken.balanceOf(feeCollector), 17.142857142857141760e18);
        assertEq(skyFarm2RewardsToken.balanceOf(swapper), 407.142857142857116800e18);
    }
}

contract OrigamiSuperSavingsUsdsManagerTestViews is OrigamiSuperSavingsUsdsManagerTestBase {
    function test_supportsInterface() public {
        assertEq(manager.supportsInterface(type(IOrigamiSuperSavingsUsdsManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }

    function test_totalAssets_multiple() public {
        // Bob deposits some into sUSDS just to bootstrap it
        {
            vm.startPrank(bob);
            deal(address(asset), bob, 1_000e18, true);
            asset.approve(address(sUSDS), 1_000e18);
            sUSDS.deposit(1_000e18, bob);
        }

        // Only counts any current USDS deposit donations (or from swaps)
        // and the current farm index deposits.
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);

        // Will have sUSDS
        deal(address(asset), address(manager), 111e18, true);
        depositAll();

        assertEq(asset.balanceOf(address(sUSDS)), BOOTSTRAPPED_USDS_AMOUNT + 1_000e18 + 111e18);
        assertEq(sUSDS.convertToAssets(1e18), 1e18);

        // USDS donation
        deal(address(asset), address(manager), asset.balanceOf(address(manager)) + 22.2e18, true);

        assertEq(manager.totalAssets(), 111e18+22.2e18);

        // A bit of interest
        skip(SWITCH_FARM_COOLDOWN);
        assertEq(sUSDS.convertToAssets(1e18), 1.000136986301369863e18);
        assertEq(manager.totalAssets(), 111e18+22.2e18 + 0.015205479452054794e18);

        // Switch to farm 1
        manager.switchFarms(1);
        assertEq(sUSDS.convertToAssets(1e18), 1.000136986301369863e18);

        deal(address(asset), address(manager), asset.balanceOf(address(manager)) + 13e18, true);
        deal(address(sUSDS), address(manager), sUSDS.balanceOf(address(manager)) + 9e18, true);
        assertEq(manager.totalAssets(), 111e18+22.2e18 + 0.015205479452054794e18 + 13e18 + 9e18 - 0.079055622683519557e18);
    }

    function test_farmViewsPartial() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(skyFarm1), 123), 1);
        assertEq(manager.addFarm(address(skyFarm2), 456), 2);
        deal(address(asset), address(manager), 100e18);
        assertEq(depositAll(), 100e18);

        uint32[] memory farmIndexes = new uint32[](3);
        farmIndexes[0] = 0;
        farmIndexes[1] = 3;
        farmIndexes[2] = 2;
        IOrigamiSuperSavingsUsdsManager.FarmDetails[] memory farmDetails = manager.farmDetails(farmIndexes);
        assertEq(farmDetails.length, 3);

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.05e18);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
        
        {
            IOrigamiSuperSavingsUsdsManager.FarmDetails memory details = farmDetails[2];
            assertEq(address(details.farm.staking), address(skyFarm2));
            assertEq(address(details.farm.rewardsToken), address(skyFarm2RewardsToken));
            assertEq(details.farm.referral, 456);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.004960317460317460e18);
            assertEq(details.unclaimedRewards, 0);
        }
    }
}
