pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiSuperSkyManager } from "contracts/investments/sky/OrigamiSuperSkyManager.sol";
import { IOrigamiSuperSkyManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSkyManager.sol";
import { TokenPrices } from "contracts/common/TokenPrices.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { DummySkyStakingRewards } from "contracts/test/external/maker/DummySkyStakingRewards.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { stdError } from "forge-std/StdError.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISkyLockstakeEngine } from "contracts/interfaces/external/sky/ISkyLockstakeEngine.sol";
import { ISkyStakingRewards } from "contracts/interfaces/external/sky/ISkyStakingRewards.sol";
import { LSE_WITH_FEE } from "test/foundry/unit/investments/sky/LseWithFee.t.sol";

contract OrigamiSuperSkyManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    IERC20 internal constant SKY = IERC20(0x56072C95FAA701256059aa122697B133aDEd9279);
    IERC20 internal constant LSSKY = IERC20(0xf9A9cfD3229E985B91F99Bc866d42938044FFa1C);
    ISkyLockstakeEngine internal constant LOCKSTAKE_ENGINE = ISkyLockstakeEngine(0xCe01C90dE7FD1bcFa39e237FE6D8D9F569e8A6a3);
    address internal constant LSE_WARD = 0x35526314F18FeB5b7F124e40D6A99d64F7D7e89a;
    address internal URN_ADDRESS;

    ISkyStakingRewards internal constant FARM1 = DummySkyStakingRewards(0x38E4254bD82ED5Ee97CD1C4278FAae748d998865);
    IERC20 internal constant FARM1_REWARDS_TOKEN = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F); // USDS

    OrigamiDelegated4626Vault public vault;
    OrigamiSuperSkyManager public manager;

    TokenPrices public tokenPrices;
    address public swapper = makeAddr("swapper");

    DummySkyStakingRewards public FARM2;
    DummyMintableToken public FARM2_REWARDS_TOKEN;

    uint96 public constant SUSDS_INTEREST_RATE = 0.05e18;
    uint32 public constant SWITCH_FARM_COOLDOWN = 1 days;
    uint16 public constant PERF_FEE_FOR_CALLER = 100; // 1%
    uint16 public constant PERF_FEE_FOR_ORIGAMI = 400; // 4%

    uint256 public constant DEPOSIT_FEE = 0;

    event InKindFees(IOrigamiErc4626.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        fork("mainnet", 22694300);

        tokenPrices = new TokenPrices(30);
        vault = new OrigamiDelegated4626Vault(
            origamiMultisig, 
            "Origami SKY Auto-Compounder", 
            "oAC-SKY-a",
            SKY,
            address(tokenPrices)
        );

        manager = new OrigamiSuperSkyManager(
            origamiMultisig,
            address(vault),
            address(LOCKSTAKE_ENGINE),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            PERF_FEE_FOR_CALLER,
            PERF_FEE_FOR_ORIGAMI
        );
        URN_ADDRESS = manager.URN_ADDRESS();

        FARM2_REWARDS_TOKEN = new DummyMintableToken(origamiMultisig, "SUBDAO1", "SUBDAO1", 18);
        FARM2 = new DummySkyStakingRewards(address(FARM2_REWARDS_TOKEN), address(LSSKY));
        vm.prank(LSE_WARD);
        LOCKSTAKE_ENGINE.addFarm(address(FARM2));
        deal(address(FARM2_REWARDS_TOKEN), address(FARM2), 3_000e18);
        FARM2.notifyRewardAmount(3_000e18);
        
        vm.startPrank(origamiMultisig);
        vault.setManager(address(manager), 0);
        vm.stopPrank();
    }

    function setupAndSwitchFarm() internal {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();
        vm.startPrank(origamiMultisig);
        manager.switchFarms(1);
    }

    function notifyRewards() internal {
        uint256 amount = 500_000e18;
        deal(address(FARM1_REWARDS_TOKEN), address(FARM1), amount, true);
        vm.startPrank(FARM1.rewardsDistribution());
        FARM1.notifyRewardAmount(amount);
    }

    function deposit(uint256 amount) internal returns (uint256) {
        deal(address(SKY), address(manager), amount);
        return manager.deposit(amount);
    }

    function allFarmDetails() internal view returns (IOrigamiSuperSkyManager.FarmDetails[] memory details) {
        uint256 length = manager.maxFarmIndex() + 1;
        uint32[] memory farmIndexes = new uint32[](length);
        for (uint32 i; i < length; ++i) {
            farmIndexes[i] = i;
        }

        return manager.farmDetails(farmIndexes);
    }
}

contract OrigamiSuperSkyManagerTestAdmin is OrigamiSuperSkyManagerTestBase {
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
        new OrigamiSuperSkyManager(
            origamiMultisig,
            address(vault),
            address(LOCKSTAKE_ENGINE),
            SWITCH_FARM_COOLDOWN,
            swapper,
            feeCollector,
            9_000,
            1_001
        );
    }

    function test_initialization() public view {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(manager.asset(), address(SKY));
        assertEq(address(manager.SKY()), address(SKY));
        assertEq(address(manager.LSSKY()), address(LSSKY));
        assertEq(address(manager.LOCKSTAKE_ENGINE()), address(LOCKSTAKE_ENGINE));
        assertNotEq(address(manager.URN_ADDRESS()), address(0));
        assertEq(manager.totalAssets(), 0);
        assertEq(manager.maxFarmIndex(), 0);
        assertEq(manager.currentFarmIndex(), 0);
        assertEq(manager.switchFarmCooldown(), SWITCH_FARM_COOLDOWN);
        assertEq(manager.lastSwitchTime(), 1749801587);
        assertEq(manager.swapper(), swapper);
        assertEq(manager.feeCollector(), feeCollector);
        (uint16 forCaller, uint16 forOrigami) = manager.performanceFeeBps();
        assertEq(forCaller, 100);
        assertEq(forOrigami, 400);
        assertEq(manager.withdrawalFeeBps(), 0);
        assertEq(manager.depositFeeBps(), 0);
        assertEq(manager.stakedBalance(), 0);
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), false);

        // Not setup by default
        IOrigamiSuperSkyManager.Farm memory farm = manager.getFarm(0);
        assertEq(address(farm.staking), address(0));
        assertEq(address(farm.rewardsToken), address(0));
        assertEq(farm.referral, 0);

        // Max approval set for 
        assertEq(SKY.allowance(address(manager), address(LOCKSTAKE_ENGINE)), type(uint256).max);
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

        assertEq(deposit(1_000_000e18), 1_000_000e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN), 
            0.6423418783239e18,
            2.5693675132956e18,
            61.0224784407705e18
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
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 0.6423418783239e18 + 2.5693675132956e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(origamiMultisig), 0);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(swapper), 61.0224784407705e18);
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
            DummySkyStakingRewards farm = new DummySkyStakingRewards(address(FARM1_REWARDS_TOKEN), address(LSSKY));
            manager.addFarm(address(farm), uint16(i));
        }

        assertGt(uint160(address(manager.getFarm(100).staking)), 0);
        assertEq(uint160(address(manager.getFarm(101).staking)), 0);

        // Last one will fail
        {
            DummySkyStakingRewards farm = new DummySkyStakingRewards(address(FARM1_REWARDS_TOKEN), address(LSSKY));
            vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.MaxFarms.selector));
            manager.addFarm(address(farm), 100);
        }
    }

    function test_addFarm_failNotUnique() public {
        vm.startPrank(origamiMultisig);
        DummySkyStakingRewards farm;
        for (uint256 i; i < 55; ++i) {
            farm = new DummySkyStakingRewards(address(FARM1_REWARDS_TOKEN), address(LSSKY));
            manager.addFarm(address(farm), uint16(i));
        }

        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.FarmExistsAlready.selector, address(farm)));
        manager.addFarm(address(farm), 100);
    }

    function test_addFarm_failZeroAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 1));
        manager.addFarm(address(0), 0);
    }

    function test_addFarm_failWrongFarmToken() public {
        DummySkyStakingRewards badFarm = new DummySkyStakingRewards(address(FARM1_REWARDS_TOKEN), address(FARM2_REWARDS_TOKEN));

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 1));
        manager.addFarm(address(badFarm), 0);
    }

    function test_addFarm_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FarmAdded(1, address(FARM1), address(FARM1_REWARDS_TOKEN), 123);

        // Index starts at 1
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        // Index 0 is empty
        {
            IOrigamiSuperSkyManager.Farm memory farm = manager.getFarm(0);
            assertEq(address(farm.staking), address(0));
            assertEq(address(farm.rewardsToken), address(0));
            assertEq(farm.referral, 0);
        }

        // Index 1 has this new farm
        {
            IOrigamiSuperSkyManager.Farm memory farm = manager.getFarm(1);
            assertEq(address(farm.staking), address(FARM1));
            assertEq(address(farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(farm.referral, 123);
        }

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);

        // Index 0 has the SKY => LSSKY in the urn
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);

            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_784_034_923.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }

        // Index 1 has this new farm
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];

            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);

            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_783_016_843.252905107379963658e18);
            assertEq(details.rewardRate, 2.893518518518518518e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.maxFarmIndex(), 1); // new farm
        assertEq(manager.currentFarmIndex(), 0); // hasn't switched
    }

    function test_removeFarm_failures() public {
        vm.startPrank(origamiMultisig);

        // Adding the same farm to a different slot 
        manager.addFarm(address(FARM1), 1);
        manager.addFarm(address(FARM2), 2);

        assertEq(manager.maxFarmIndex(), 2); // new farm
        assertEq(manager.currentFarmIndex(), 0); // hasn't switched

        // Can't remove farm zero
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.FarmStillInUse.selector, 0));
        manager.removeFarm(0);

        // Not added yet
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 69));
        manager.removeFarm(69);
        
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(2);
        assertEq(manager.currentFarmIndex(), 2);

        // Still can't remove farm zero
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 0));
        manager.removeFarm(0);

        // Still can't remove farm 2, it's in use
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.FarmStillInUse.selector, 2));
        manager.removeFarm(2);

        // Stake (into 2)
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        // Alice deposits into 1 on behalf of
        // NB: This could be used as a sort of DoS to remove the farm, but it can be solved via msig in a single tx:
        // 1/ Switch to that farm
        // 2/ Switch back to a different farm: This will claim rewards and unstake that notional
        {
            vm.startPrank(alice);
            SKY.approve(address(LOCKSTAKE_ENGINE), 100e18);
            deal(address(SKY), alice, 100e18);
            LOCKSTAKE_ENGINE.lock(address(manager), 0, 100e18, 0);
        }

        // Can't remove from 1 either, even though it's not the current farm.
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.FarmStillInUse.selector, 1));
        manager.removeFarm(1);

        // Switch back to just holding LSSKY which will unstake from farm 2
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(0);

        vm.assertEq(FARM2.earned(URN_ADDRESS), 0);
        vm.mockCall(
            address(FARM2),
            abi.encodeWithSelector(ISkyStakingRewards.earned.selector, URN_ADDRESS),
            abi.encode(100e18)
        );
        vm.assertEq(FARM2.earned(URN_ADDRESS), 100e18);

        // Still can't remove as there's an earned balance of rewards to claim first.
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.FarmStillInUse.selector, 2));
        manager.removeFarm(2);

        vm.mockCall(
            address(FARM2),
            abi.encodeWithSelector(ISkyStakingRewards.earned.selector, URN_ADDRESS),
            abi.encode(0)
        );
        vm.assertEq(FARM2.earned(URN_ADDRESS), 0);

        uint32[] memory farmIndexes = new uint32[](2);
        farmIndexes[0] = 1;
        farmIndexes[1] = 2;
        manager.claimFarmRewards(farmIndexes, origamiMultisig);
        manager.removeFarm(2);
        manager.removeFarm(1);
    }

    function test_removeFarm_success() public {
        vm.startPrank(origamiMultisig);

        // Adding the same farm to a different slot 
        manager.addFarm(address(FARM1), 1);
        manager.addFarm(address(FARM2), 2);

        assertEq(SKY.allowance(address(manager), address(FARM1)), 0);
        assertEq(SKY.allowance(address(manager), address(FARM2)), 0);

        vm.expectEmit(address(manager));
        emit FarmRemoved(2, address(FARM2), address(FARM2_REWARDS_TOKEN));
        manager.removeFarm(2);
        assertEq(SKY.allowance(address(manager), address(FARM1)), 0);
        assertEq(SKY.allowance(address(manager), address(FARM2)), 0);

        // Farm 1 is still there
        IOrigamiSuperSkyManager.Farm memory farm = manager.getFarm(1);
        assertEq(address(farm.staking), address(FARM1));
        assertEq(address(farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
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
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 1));
        manager.setFarmReferralCode(1, 1);
    }

    function test_setFarmReferralCode_farmSuccess() public {
        vm.startPrank(origamiMultisig);
        manager.addFarm(address(FARM1), 1);
        vm.expectEmit(address(manager));
        emit FarmReferralCodeSet(1, 123);
        manager.setFarmReferralCode(1, 123);
        
        IOrigamiSuperSkyManager.Farm memory farm = manager.getFarm(1);
        assertEq(address(farm.staking), address(FARM1));
        assertEq(address(farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
        assertEq(farm.referral, 123);
    }

    function test_recoverToken_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(SKY)));
        manager.recoverToken(address(SKY), alice, 100e18);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }
}

contract OrigamiSuperSkyManagerTestAccess is OrigamiSuperSkyManagerTestBase {
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

    // NB: Anyone can call deposit, but only the vault can withdraw
    function test_withdraw_access() public {
        expectElevatedAccess();
        manager.withdraw(100, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.withdraw(100, alice);
    }

    function test_switchFarms_access() public {
        expectElevatedAccess();
        manager.switchFarms(1);
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

contract OrigamiSuperSkyManagerTestDeposit is OrigamiSuperSkyManagerTestBase {
    event Lock(address indexed owner, uint256 indexed index, uint256 wad, uint16 ref);

    function test_deposit_pausedOK() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));

        assertEq(manager.areDepositsPaused(), true);
        assertEq(manager.areWithdrawalsPaused(), false);

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(manager.deposit(0), 0);
    }

    function test_deposit_successNothing() public {
        assertEq(manager.deposit(0), 0);
    }

    function test_deposit_fail_tooMuch() public {
        vm.expectRevert("Sky/insufficient-balance");
        manager.deposit(100e18);
    }

    function test_deposit_successLimitedSky() public {
        vm.startPrank(origamiMultisig);
        deal(address(SKY), address(manager), 100e18);
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 25e18, 0);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 25e18);
        assertEq(SKY.balanceOf(address(manager)), 75e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
        
        assertEq(address(details.farm.staking), address(0));
        assertEq(address(details.farm.rewardsToken), address(0));
        assertEq(details.farm.referral, 0);
        assertEq(details.stakedBalance, 25e18);
        assertEq(details.totalSupply, 7_784_034_948.252905107379963658e18);
        assertEq(details.rewardRate, 0);
        assertEq(details.unclaimedRewards, 0);
    }

    function test_deposit_successSkyReferral() public {
        vm.startPrank(origamiMultisig);
        manager.setFarmReferralCode(0, 123);
        deal(address(SKY), address(manager), 100e18);
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 25e18, 123);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 25e18);
        assertEq(SKY.balanceOf(address(manager)), 75e18);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
        
        assertEq(address(details.farm.staking), address(0));
        assertEq(address(details.farm.rewardsToken), address(0));
        assertEq(details.farm.referral, 0);
        assertEq(details.stakedBalance, 25e18);
        assertEq(details.totalSupply, 7_784_034_948.252905107379963658e18);
        assertEq(details.rewardRate, 0);
        assertEq(details.unclaimedRewards, 0);
    }

    function test_deposit_successMaxSky() public {
        vm.startPrank(origamiMultisig);
        deal(address(SKY), address(manager), 100e18);
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 100e18, 0);
        assertEq(manager.deposit(100e18), 100e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 100e18);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(manager.totalAssets(), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_784_035_023.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
    }

    function test_deposit_failZeroAmount() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        vm.expectRevert("Cannot stake 0");
        manager.deposit(0);
    }

    function test_deposit_successFARM1_limited() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 0), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(SKY), address(manager), 100e18);

        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 25e18, 0);
        assertEq(manager.deposit(25e18), 25e18);
        assertEq(SKY.balanceOf(address(manager)), 75e18);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 0);
        assertEq(FARM1.balanceOf(URN_ADDRESS), 25e18);
        assertEq(manager.totalAssets(), 100e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 25e18);
            assertEq(details.totalSupply, 7_783_016_868.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0.001606061018701850e18);
        }
    }

    function test_deposit_successFARM1_noReferral() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 0), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(SKY), address(manager), 100e18);

        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 100e18, 0);
        assertEq(manager.deposit(100e18), 100e18);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 0);
        assertEq(FARM1.balanceOf(URN_ADDRESS), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_783_016_943.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0.006424244012901000e18);
        }
    }

    function test_deposit_successFARM1_withReferral() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        deal(address(SKY), address(manager), 100e18);

        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Lock(address(manager), 0, 100e18, 123);
        assertEq(manager.deposit(100e18), 100e18);
        assertEq(SKY.balanceOf(address(manager)), 0);
        assertEq(LSSKY.balanceOf(URN_ADDRESS), 0);
        assertEq(FARM1.balanceOf(URN_ADDRESS), 100e18);
        assertEq(manager.totalAssets(), 100e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_783_016_943.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0.006424244012901000e18);
        }
    }
}

contract OrigamiSuperSkyManagerTestWithdraw is OrigamiSuperSkyManagerTestBase {
    event Free(address indexed owner, uint256 indexed index, address to, uint256 wad, uint256 freed);

    function test_withdraw_pausedOK() public {
        assertEq(deposit(100e18), 100e18);

        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));

        assertEq(manager.areDepositsPaused(), false);
        assertEq(manager.areWithdrawalsPaused(), true);
        vm.startPrank(address(vault));

        // The manager itself doesn't pause - it's checked within the OrigamiERC4626
        assertEq(manager.withdraw(100, alice), 100);
    }

    function test_withdraw_sky_successNothing() public {
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(0, alice), 0);
    }

    function test_withdraw_sky_failNotEnough() public {
        vm.startPrank(address(vault));
        vm.expectRevert("LockstakeSky/insufficient-balance");
        manager.withdraw(100e18, alice);
    }

    function test_withdraw_sky_success() public {
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        uint256 totalAssets = manager.totalAssets();
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Free(address(manager), 0, alice, 100e18, 100e18);
        assertEq(manager.withdraw(totalAssets, alice), 100e18);

        assertEq(SKY.balanceOf(alice), 100e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_784_034_923.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
        
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_sky_maxFail() public {
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        vm.expectRevert("LockstakeEngine/overflow");
        manager.withdraw(type(uint256).max, alice);
    }

    function test_withdraw_sky_successSameReceiver() public {
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Free(address(manager), 0, address(manager), 50e18, 50e18);
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);

        assertEq(SKY.balanceOf(address(manager)), 50e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 50e18);
            assertEq(details.totalSupply, 7_784_034_973.252905107379963658e18);
            assertEq(details.rewardRate, 0);
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
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(manager.totalAssets(), alice), 100e18);

        assertEq(SKY.balanceOf(alice), 100e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_783_016_843.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0.006424244012901000e18);
        }
        assertEq(manager.totalAssets(), 0);
    }

    function test_withdraw_farm_maxFail() public {
        setupAndSwitchFarm();
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        vm.expectRevert("LockstakeEngine/overflow");
        manager.withdraw(type(uint256).max, alice);
    }

    function test_withdraw_farm_successSameReceiver() public {
        setupAndSwitchFarm();
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));
        assertEq(manager.withdraw(50e18, address(manager)), 50e18);

        assertEq(SKY.balanceOf(address(manager)), 50e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 50e18);
            assertEq(details.totalSupply, 7_783_016_893.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0.009636366039986950e18);
        }
        assertEq(manager.totalAssets(), 100e18);
    }
}

contract OrigamiSuperSkyManagerTestSwitch is OrigamiSuperSkyManagerTestBase {
    event SwitchedFarms(
        uint32 indexed oldFarmIndex, 
        uint32 indexed newFarmIndex, 
        uint256 amountWithdrawn, 
        uint256 amountDeposited
    );

    event ClaimedReward(
        uint32 indexed farmIndex, 
        address indexed rewardsToken, 
        uint256 amountForCaller, 
        uint256 amountForOrigami, 
        uint256 amountForVault
    );

    function test_switchFarms_failBeforeCooldown() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN-1);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.BeforeCooldownEnd.selector));
        manager.switchFarms(1);
    }

    function test_switchFarms_failSwitchToTheSame() public {
        vm.startPrank(origamiMultisig);
        skip(SWITCH_FARM_COOLDOWN);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 0));
        manager.switchFarms(0);
    }

    function test_switchFarms_failNotSetup() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiSuperSkyManager.InvalidFarm.selector, 2));
        manager.switchFarms(2);
    }

    function test_switchFarms_skyToFarm_noBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 0, 0);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 0);
        assertEq(deposited, 0);
    }

    function test_switchFarms_skyToFarm_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        assertEq(SKY.allowance(address(manager), address(LOCKSTAKE_ENGINE)), type(uint256).max);
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 100e18);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_784_035_023.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_783_016_943.252905107379963658e18);
            assertEq(details.rewardRate, 2.893518518518518518e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 1);
        assertEq(manager.lastSwitchTime(), block.timestamp);
        assertEq(SKY.allowance(address(manager), address(LOCKSTAKE_ENGINE)), type(uint256).max);
    }

    function test_switchFarms_skyToFarm_withDonation() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        assertEq(deposit(100e18), 100e18);

        // Slide in another donation
        deal(address(SKY), address(manager), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(0, 1, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(1);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 200e18);
        assertEq(manager.unallocatedAssets(), 100e18);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 2);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_784_035_023.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_783_016_943.252905107379963658e18);
            assertEq(details.rewardRate, 2.893518518518518518e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 1);
        assertEq(manager.lastSwitchTime(), block.timestamp);
    }

    function test_switchFarms_farmToFarm_noBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
        
        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(1, 2, 0, 0);
        manager.switchFarms(2);
    }

    function test_switchFarms_farmToFarm_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.expectEmit(address(manager));
        emit SwitchedFarms(1, 2, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(2);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 100e18);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 3);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_783_016_843.252905107379963658e18);
            assertEq(details.rewardRate, 2.893518518518518518e18);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[2];
            assertEq(address(details.farm.staking), address(FARM2));
            assertEq(address(details.farm.rewardsToken), address(FARM2_REWARDS_TOKEN));
            assertEq(details.farm.referral, 456);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 100e18);
            assertEq(details.rewardRate, 0.004960317460317460e18);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 2);
        assertEq(manager.lastSwitchTime(), block.timestamp);
    }

    function test_switchFarms_farmToSky_withBalance() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);

        assertEq(deposit(100e18), 100e18);

        notifyRewards();
        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN), 
            0.000064242440129010e18,
            0.000256969760516040e18,
            0.006103031812255950e18
        );
        vm.expectEmit(address(manager));
        emit SwitchedFarms(1, 0, 100e18, 100e18);
        (uint256 withdrawn, uint256 deposited) = manager.switchFarms(0);
        assertEq(withdrawn, 100e18);
        assertEq(deposited, 100e18);
        assertEq(manager.totalAssets(), 100e18);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 3);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(FARM1));
            assertEq(address(details.farm.rewardsToken), address(FARM1_REWARDS_TOKEN));
            assertEq(details.farm.referral, 123);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_783_016_843.252905107379963658e18);
            assertEq(details.rewardRate, 289.351851851851851851e18);
            assertEq(details.unclaimedRewards, 0); // claimed when switching
            assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 0.000064242440129010e18 + 0.000256969760516040e18);
        }

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_784_035_023.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }

        assertEq(manager.currentFarmIndex(), 0);
        assertEq(manager.lastSwitchTime(), block.timestamp);
    }
}

contract OrigamiSuperSkyManagerTestRewards is OrigamiSuperSkyManagerTestBase {
    event ClaimedReward(
        uint32 indexed farmIndex, 
        address indexed rewardsToken, 
        uint256 amountForCaller, 
        uint256 amountForOrigami, 
        uint256 amountForVault
    );
    event Reinvest(uint256 amount);
    event GetReward(address indexed owner, uint256 indexed index, address indexed farm, address to, uint256 amt);

    function test_claimFarmRewards_successNoIndexes() public {
        manager.claimFarmRewards(new uint32[](0), origamiMultisig);
    }

    function test_claimFarmRewards_failIndex() public {
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 0;

        // Doesn't revert, nothing done
        manager.claimFarmRewards(indexes, origamiMultisig);
    }

    function test_claimFarmRewards_removedFarm() public {
        vm.startPrank(origamiMultisig);
        manager.addFarm(address(FARM1), 0);
        manager.addFarm(address(FARM2), 0);
        vm.stopPrank();

        uint32[] memory indexes = new uint32[](4);
        indexes[0] = 0;
        indexes[1] = 1;
        indexes[2] = 2;
        indexes[3] = 3;
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit GetReward(address(manager), 0, address(FARM1), address(manager), 0);
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit GetReward(address(manager), 0, address(FARM2), address(manager), 0);
        manager.claimFarmRewards(indexes, origamiMultisig);

        vm.prank(origamiMultisig);
        manager.removeFarm(1);
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit GetReward(address(manager), 0, address(FARM2), address(manager), 0);
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

        assertEq(deposit(1_000_000e18), 1_000_000e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 1;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN),
            0.642341878323900000e18,
            2.569367513295600000e18,
            61.022478440770500000e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(FARM1_REWARDS_TOKEN.balanceOf(alice), 0.642341878323900000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 2.569367513295600000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(swapper), 61.022478440770500000e18);
    }

    function test_claimFarmRewards_successDifferentRecipient() public {
        setupAndSwitchFarm();

        assertEq(deposit(1_000_000e18), 1_000_000e18);
        skip(SWITCH_FARM_COOLDOWN);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](1);
        indexes[0] = 1;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN),
            0.642341878323900000e18,
            2.569367513295600000e18,
            61.022478440770500000e18
        );
        manager.claimFarmRewards(indexes, bob);

        assertEq(FARM1_REWARDS_TOKEN.balanceOf(alice), 0);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(bob), 0.642341878323900000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 2.569367513295600000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(swapper), 61.022478440770500000e18);
    }

    function test_claimFarmRewards_successMultiple() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        manager.switchFarms(1);
        notifyRewards();

        assertEq(deposit(1_000_000e18), 1_000_000e18);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();
        vm.startPrank(origamiMultisig);

        // Switching farms claims the rewards
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN), 
            0.642341878323900000e18,
            2.569367513295600000e18,
            61.022478440770500000e18
        );
        manager.switchFarms(2);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            2, 
            address(FARM2_REWARDS_TOKEN), 
            4.285714285714280000e18,
            17.142857142857120000e18,
            407.142857142856600000e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(FARM1_REWARDS_TOKEN.balanceOf(alice), 0);  // all went to the fee collector when switching farms
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 2.569367513295600000e18 + 0.642341878323900000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(swapper), 61.022478440770500000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(alice), 4.285714285714280000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(feeCollector), 17.142857142857120000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(swapper), 407.142857142856600000e18);
    }

    function test_claimFarmRewards_withDonation() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();
        vm.startPrank(origamiMultisig);
        manager.switchFarms(1);

        assertEq(deposit(1_000_000e18), 1_000_000e18);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();
        vm.startPrank(origamiMultisig);

        // Switching farms claims the rewards
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            1, 
            address(FARM1_REWARDS_TOKEN), 
            0.642341878323900000e18,
            2.569367513295600000e18,
            61.022478440770500000e18
        );
        manager.switchFarms(2);
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();

        deal(address(FARM1_REWARDS_TOKEN), address(manager), 250e18);

        vm.startPrank(alice);
        uint32[] memory indexes = new uint32[](2);
        indexes[0] = 1;
        indexes[1] = 2;
        vm.expectEmit(address(manager));
        emit ClaimedReward(
            2, 
            address(FARM2_REWARDS_TOKEN), 
            4.285714285714280000e18,
            17.142857142857120000e18,
            407.142857142856600000e18
        );
        manager.claimFarmRewards(indexes, alice);

        assertEq(FARM1_REWARDS_TOKEN.balanceOf(alice), 0); // all went to the fee collector when switching farms
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(feeCollector), 2.569367513295600000e18 + 0.642341878323900000e18);
        assertEq(FARM1_REWARDS_TOKEN.balanceOf(swapper), 61.022478440770500000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(alice), 4.285714285714280000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(feeCollector), 17.142857142857120000e18);
        assertEq(FARM2_REWARDS_TOKEN.balanceOf(swapper), 407.142857142856600000e18);
    }

    function test_reinvest_nothing() public {
        assertEq(deposit(1_000_000e18), 1_000_000e18);

        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.stakedBalance(), 1_000_000e18);
        manager.reinvest();
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.stakedBalance(), 1_000_000e18);
    }

    function test_reinvest_something() public {
        assertEq(deposit(1_000_000e18), 1_000_000e18);

        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.stakedBalance(), 1_000_000e18);
        deal(address(SKY), address(manager), 5_555e18);
        assertEq(manager.unallocatedAssets(), 5_555e18);
        vm.expectEmit(address(manager));
        emit Reinvest(5_555e18);
        manager.reinvest();
        assertEq(manager.unallocatedAssets(), 0);
        assertEq(manager.stakedBalance(), 1_005_555e18);
    }
}

contract OrigamiSuperSkyManagerTestViews is OrigamiSuperSkyManagerTestBase {
    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiSuperSkyManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiManagerPausable).interfaceId), false);
    }

    function test_totalAssets_multiple() public {
        // Only counts any current SKY deposit donations (or from swaps)
        // and the current farm index deposits.
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);

        // Will have SKY
        assertEq(deposit(111e18), 111e18);

        // SKY donation
        deal(address(SKY), address(manager), SKY.balanceOf(address(manager)) + 22.2e18, true);
        assertEq(manager.totalAssets(), 111e18+22.2e18);
        assertEq(manager.stakedBalance(), 111e18);

        // Switch to farm 1
        skip(SWITCH_FARM_COOLDOWN);
        notifyRewards();
        vm.startPrank(origamiMultisig);
        manager.switchFarms(1);

        deal(address(SKY), address(manager), SKY.balanceOf(address(manager)) + 13e18, true);
        assertEq(manager.totalAssets(), 111e18+22.2e18 + 13e18);
        assertEq(manager.stakedBalance(), 111e18);
    }

    function test_farmViewsPartial() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.addFarm(address(FARM1), 123), 1);
        assertEq(manager.addFarm(address(FARM2), 456), 2);
        assertEq(deposit(100e18), 100e18);

        uint32[] memory farmIndexes = new uint32[](3);
        farmIndexes[0] = 0;
        farmIndexes[1] = 3;
        farmIndexes[2] = 2;
        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = manager.farmDetails(farmIndexes);
        assertEq(farmDetails.length, 3);

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 100e18);
            assertEq(details.totalSupply, 7_784_035_023.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }

        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[1];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
        
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[2];
            assertEq(address(details.farm.staking), address(FARM2));
            assertEq(address(details.farm.rewardsToken), address(FARM2_REWARDS_TOKEN));
            assertEq(details.farm.referral, 456);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 0);
            assertEq(details.rewardRate, 0.004960317460317460e18);
            assertEq(details.unclaimedRewards, 0);
        }
    }
}

contract OrigamiSuperSkyManagerTestWithFee is OrigamiSuperSkyManagerTestBase {
    event Free(address indexed owner, uint256 indexed index, address to, uint256 wad, uint256 freed);

    uint256 public constant UPDATED_FEE = 0.012345e18;

    function setUp() public override {
        super.setUp();

        // Etch a new lockstake engine, one with a fee of 0.012345e18
        vm.etch(address(LOCKSTAKE_ENGINE), LSE_WITH_FEE);
    }

    function test_withdrawalFeeBps() public view {
        // Rounded up to the nearest basis point
        assertEq(manager.withdrawalFeeBps(), 124);
    }

    function test_withdraw_partial() public {
        assertEq(deposit(100e18), 100e18);

        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        // uint256 totalAssets = manager.totalAssets();
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Free(address(manager), 0, alice, 10.124993039067285641e18, 10e18);
        assertEq(manager.withdraw(10e18, alice), 10e18);

        assertEq(SKY.balanceOf(alice), 10e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 89.875006960932714359e18);
            assertEq(details.totalSupply, 7_784_035_013.127912068312678017e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
        
        assertEq(manager.totalAssets(), 89.875006960932714359e18);
    }

    function test_withdraw_everything() public {
        assertEq(deposit(100e18), 100e18);
        skip(SWITCH_FARM_COOLDOWN);
        vm.startPrank(address(vault));

        uint256 totalAssets = manager.totalAssets();

        // It's not possible to withdraw 'totalAssets' naively
        vm.expectRevert("LockstakeSky/insufficient-balance");
        manager.withdraw(totalAssets, alice);

        // But it is possible if it withdraws the amount minus the fee
        uint256 totalMinusFee = totalAssets * (1e18 - UPDATED_FEE) / 1e18;
        vm.expectEmit(address(LOCKSTAKE_ENGINE));
        emit Free(address(manager), 0, alice, totalAssets, totalMinusFee);
        assertEq(manager.withdraw(totalMinusFee, alice), totalMinusFee);

        // The last withdraw simply wont get the amount it asked for.
        // However that will be Origami which seeded the vault.
        assertEq(SKY.balanceOf(alice), 98.7655e18);

        skip(SWITCH_FARM_COOLDOWN);

        IOrigamiSuperSkyManager.FarmDetails[] memory farmDetails = allFarmDetails();
        assertEq(farmDetails.length, 1);
        {
            IOrigamiSuperSkyManager.FarmDetails memory details = farmDetails[0];
            assertEq(address(details.farm.staking), address(0));
            assertEq(address(details.farm.rewardsToken), address(0));
            assertEq(details.farm.referral, 0);
            assertEq(details.stakedBalance, 0);
            assertEq(details.totalSupply, 7_784_034_923.252905107379963658e18);
            assertEq(details.rewardRate, 0);
            assertEq(details.unclaimedRewards, 0);
        }
        
        assertEq(manager.totalAssets(), 0);
    }
}
