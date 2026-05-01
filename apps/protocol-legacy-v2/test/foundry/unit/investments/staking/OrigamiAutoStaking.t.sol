pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiAutoStaking } from "contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiAutoStakingToErc4626 } from "contracts/investments/staking/OrigamiAutoStakingToErc4626.sol";
import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { OrigamiAutoStakingToErc4626Common } from "test/foundry/unit/investments/staking/OrigamiAutoStakingToErc4626Common.t.sol";
import { OrigamiAutoStaking } from "contracts/investments/staking/OrigamiAutoStaking.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { stdError } from "forge-std/StdError.sol";
import { MultiRewards } from "contracts/investments/staking/MultiRewards.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";

// eg USDT which doesn't `return (bool)` on transfer
contract AnnoyingToken {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory) {
        return "Annoying";
    }

    function symbol() external pure returns (string memory) {
        return "ANNOY";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external {
    }

    function transferFrom(address from, address to, uint256 amount) external {
        _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockMultiRewards is MultiRewards {
    using SafeERC20 for IERC20;

    constructor(address stakingToken_) MultiRewards(stakingToken_) {}
    function onStake(uint256 amount) internal override {}
    function onWithdraw(uint256 amount) internal override {}
    function onReward() internal override {}

    function addReward(address _rewardsToken, uint256 _rewardsDuration) external {
        _addReward(_rewardsToken, _rewardsDuration);
    }

    function notifyRewardAmount(address _rewardToken, uint256 _reward) external {
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _reward);
        _notifyRewardAmount(_rewardToken, _reward);
    }
}

contract OrigamiAutoStakingToErc4626TestBase is OrigamiAutoStakingToErc4626Common {
    uint256 internal constant tolerance = 1e18 / 1e12; // Example tolerance: 0.000001 ether

    function setUp() public virtual {
        fork("berachain_mainnet", BERACHAIN_FORK_BLOCK_NUMBER);        
        setUpContracts();
    }

    function stakeOnBehalfOf(
        OrigamiAutoStakingToErc4626 vault,
        address token,
        address staker,
        uint256 stakeAmount
    ) internal {
        // deal(staker, stakeAmount);
        vm.startPrank(staker);
        deal(token, staker, stakeAmount);

        // User approves the rewards vault to spend their tokens
        IERC20(token).approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);
        vm.stopPrank();
    }

    function setUpGetReward(uint256 iBgtRewardsAmount, uint256 rewardsDuration)
        internal
        returns (uint256 oriBgtRewardsAmount)
    {
        // Setup reward token in the infraredVault and mint rewards
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), rewardsDuration, 50);

        // For oribgt rewards, ibgt tokens are deposited into oribgt and transferred to rewards vault
        // So deal ibgt and harvest into oribgt
        deal(address(IBGT), address(wberaHoneyAutoStaking), iBgtRewardsAmount);
        oriBgtRewardsAmount = ORI_BGT.previewDeposit(iBgtRewardsAmount);
        wberaHoneyAutoStaking.harvestVault();
        vm.stopPrank();

        // User stakes tokens
        vm.deal(address(alice), 500e18);
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, 500e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 500e18);
        wberaHoneyAutoStaking.stake(500e18);
        vm.stopPrank();
    }

    function getOriSharesAfterDeposit(uint256 amount) internal view returns (uint256 shares) {
        shares = ORI_BGT.previewDeposit(amount);
    }
}

contract OrigamiAutoStakingToErc4626TestAccess is OrigamiAutoStakingToErc4626TestBase {

    function test_harvestVault_access() public {
        // OK when not restricted
        assertEq(wberaHoneyAutoStaking.restrictedPublicHarvest(), false);
        vm.startPrank(alice);
        wberaHoneyAutoStaking.harvestVault();

        // Restricted
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setRestrictedPublicHarvest(true);
        assertEq(wberaHoneyAutoStaking.restrictedPublicHarvest(), true);
        vm.stopPrank();

        expectElevatedAccess();
        wberaHoneyAutoStaking.harvestVault();
    }

    function test_swapCallback_access() public {
        vm.prank(origamiMultisig);
        wberaHoneyAutoStaking.setSwapper(alice);

        expectElevatedAccess();
        wberaHoneyAutoStaking.swapCallback();

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        wberaHoneyAutoStaking.swapCallback();

        vm.startPrank(alice);
        wberaHoneyAutoStaking.swapCallback();
    }

    function test_updateRewardsDuration_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), 10 days);
    }

    function test_addReward_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 30 days, 100);
    }

    function test_removeReward_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.removeReward(address(IBGT));
    }

    function test_setSwapper_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.setSwapper(alice);
    }

    function test_setRestrictedPublicHarvest_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.setRestrictedPublicHarvest(true);
    }

    function test_setPostProcessingDisabled_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.setPostProcessingDisabled(true);
    }

    function test_setPaused_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.setPaused(true, true, true);
    }

    function test_notifyRewardAmount_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), 1e18);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.recoverToken(address(IBGT), alice, 1e18);
    }

    function test_setPerformanceFees_access() public {
        expectElevatedAccess();
        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](0);
        wberaHoneyAutoStaking.setPerformanceFees(fees);
    }

    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        wberaHoneyAutoStaking.setFeeCollector(alice);
    }
}

contract OrigamiAutoStakingToErc4626TestAdmin is OrigamiAutoStakingToErc4626TestBase {
    function test_initialization_autostaker() public view {
        assertEq(ohmHoneyAutoStaking.owner(), origamiMultisig);
        assertEq(address(ohmHoneyAutoStaking.stakingToken()), address(OHM_HONEY));
        assertEq(address(ohmHoneyAutoStaking.rewardsVault()), address(IR_OHM_HONEY));
        assertEq(address(ohmHoneyAutoStaking.underlyingPrimaryRewardToken()), address(IBGT));
        assertEq(address(ohmHoneyAutoStaking.primaryRewardToken()), address(ORI_BGT));
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(address(IBGT)), 0);
        assertEq(ohmHoneyAutoStaking.MAX_PERFORMANCE_FEE_BPS(), 100);
        assertEq(ohmHoneyAutoStaking.restrictedPublicHarvest(), false);
        assertEq(ohmHoneyAutoStaking.totalSupply(), 1);
        assertEq(ohmHoneyAutoStaking.balanceOf(origamiMultisig), 1);
        (, uint256 rewardsDuration,,,,,) = ohmHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertEq(rewardsDuration, REWARDS_DURATION);
        assertEq(OHM_HONEY.allowance(address(ohmHoneyAutoStaking), address(IR_OHM_HONEY)), type(uint256).max);

        assertEq(wberaHoneyAutoStaking.owner(), origamiMultisig);
        assertEq(address(wberaHoneyAutoStaking.stakingToken()), address(WBERA_HONEY));
        assertEq(address(wberaHoneyAutoStaking.rewardsVault()), address(IR_WBERA_HONEY));
        assertEq(address(wberaHoneyAutoStaking.underlyingPrimaryRewardToken()), address(IBGT));
        assertEq(wberaHoneyAutoStaking.primaryRewardToken(), address(ORI_BGT));
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(address(IBGT)), 0);
        assertEq(wberaHoneyAutoStaking.MAX_PERFORMANCE_FEE_BPS(), 100);
        assertEq(wberaHoneyAutoStaking.restrictedPublicHarvest(), false);
        assertEq(wberaHoneyAutoStaking.totalSupply(), 1);
        assertEq(wberaHoneyAutoStaking.balanceOf(origamiMultisig), 1);
        (, rewardsDuration,,,,,) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertEq(rewardsDuration, REWARDS_DURATION);
        assertEq(WBERA_HONEY.allowance(address(wberaHoneyAutoStaking), address(IR_WBERA_HONEY)), type(uint256).max);
        assertEq(wberaHoneyAutoStaking.postProcessingDisabled(), false);

        (bool onStake_, bool onWithdraw_, bool onGetReward_) = wberaHoneyAutoStaking.isPaused();
        assertFalse(onStake_);
        assertFalse(onWithdraw_);
        assertFalse(onGetReward_);
    }

    function test_constructor_revertWithZeroAddresses() public {
        // Test each parameter with zero address
        address[] memory testAddresses = new address[](8);
        testAddresses[0] = address(0); // Zero admin address
        testAddresses[1] = address(WBERA);
        testAddresses[2] = address(2); // Infrared address
        testAddresses[3] = address(3); // Pool address
        testAddresses[4] = address(origamiMultisig);
        testAddresses[5] = address(origamiMultisig);
        testAddresses[6] = address(4); // Zero admin address
        testAddresses[7] = address(5); // Zero admin address

        for (uint256 i = 0; i < testAddresses.length; i++) {
            address[] memory constructorParams = new address[](8);
            for (uint256 j = 0; j < constructorParams.length; j++) {
                constructorParams[j] = (i == j) ? address(0) : testAddresses[j];
            }
            // Act & Assert
            vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
            new OrigamiAutoStakingToErc4626(
                OrigamiAutoStaking.ConstructorArgs({
                    initialOwner: origamiMultisig,
                    stakingToken: constructorParams[0],
                    primaryRewardToken: address(ORI_BGT),
                    rewardsVault: address(IR_OHM_HONEY),
                    primaryPerformanceFeeBps: DEFAULT_FEE_BPS,
                    feeCollector: origamiMultisig,
                    rewardsDuration: 1 days,
                    swapper: address(0)
                }),
                address(IBGT)
            );
        }
    }

    function test_constructor_badStakingAsset() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, alice));
        new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: alice, // doesn't match rewards vault
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_OHM_HONEY),
                primaryPerformanceFeeBps: DEFAULT_FEE_BPS,
                feeCollector: origamiMultisig,
                rewardsDuration: 1 days,
                swapper: address(0)
            }),
            address(IBGT)
        );
    }

    function test_acceptOwner_transferInitialBalance() public {
        assertEq(ohmHoneyAutoStaking.owner(), origamiMultisig);
        assertEq(ohmHoneyAutoStaking.balanceOf(origamiMultisig), 1);
        assertEq(ohmHoneyAutoStaking.balanceOf(bob), 0);

        vm.prank(origamiMultisig);
        ohmHoneyAutoStaking.proposeNewOwner(bob);
        assertEq(ohmHoneyAutoStaking.owner(), origamiMultisig);
        assertEq(ohmHoneyAutoStaking.balanceOf(origamiMultisig), 1);
        assertEq(ohmHoneyAutoStaking.balanceOf(bob), 0);

        vm.prank(bob);
        ohmHoneyAutoStaking.acceptOwner();
        assertEq(ohmHoneyAutoStaking.owner(), bob);
        assertEq(ohmHoneyAutoStaking.balanceOf(origamiMultisig), 0);
        assertEq(ohmHoneyAutoStaking.balanceOf(bob), 1);
    }

    function test_constructor_revertWithZeroRewardsDuration() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: address(OHM_HONEY),
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_OHM_HONEY),
                primaryPerformanceFeeBps: 10,
                feeCollector: origamiMultisig,
                rewardsDuration: 0, // too low
                swapper: address(0)
            }),
            address(IBGT)
        );
    }

    function test_constructor_revertWithHighPerformanceFee() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiAutoStakingToErc4626(
            OrigamiAutoStaking.ConstructorArgs({
                initialOwner: origamiMultisig,
                stakingToken: address(OHM_HONEY),
                primaryRewardToken: address(ORI_BGT),
                rewardsVault: address(IR_OHM_HONEY),
                primaryPerformanceFeeBps: 101, // too high
                feeCollector: origamiMultisig,
                rewardsDuration: 1 days,
                swapper: address(0)
            }),
            address(IBGT)
        );
    }

    function test_addReward_revertWithZeroAddressForToken() public {
        uint256 rewardsDuration = 30 days;

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        wberaHoneyAutoStaking.addReward(address(0), rewardsDuration, 100);
        vm.stopPrank();
    }

    function test_addReward_revertWithUnderlyingPrimaryRewardToken() public {
        uint256 rewardsDuration = 30 days;

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(IBGT)));
        wberaHoneyAutoStaking.addReward(address(IBGT), rewardsDuration, 100);
        vm.stopPrank();
    }

    function test_addReward_revertWithZeroDuration() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 0, 100);
        vm.stopPrank();
    }

    function test_addReward_mock_revertWithZeroDuration() public {
        vm.startPrank(origamiMultisig);
        // Ensure the underlying MultiRewards::_addToken() also checks
        MockMultiRewards mockStaking = new MockMultiRewards(address(WBERA_HONEY));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        mockStaking.addReward(address(OTHER_REWARD_TOKEN), 0);
        vm.stopPrank();
    }

    function test_addReward_revertAlreadyAdded() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.RewardAlreadyExists.selector));
        wberaHoneyAutoStaking.addReward(address(ORI_BGT), 30 days, 100);
    }

    function test_addReward_revertWithMaxRewardToken() public {
        uint256 rewardsDuration = 30 days;

        vm.startPrank(origamiMultisig);
        // 2 rewards already added
        for (uint160 i = 0; i < 9; i++) {
            DummyMintableToken rToken = new DummyMintableToken(origamiMultisig, "REWARD", "REWARD", 18);
            wberaHoneyAutoStaking.addReward(address(rToken), rewardsDuration, 100);
        }
        // Now reached max reward tokens
        vm.expectRevert(abi.encodeWithSignature("MaxNumberOfRewards()"));
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), rewardsDuration, 100);
    }

    function test_addReward_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardStored(address(OTHER_REWARD_TOKEN), 30 days);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 30 days, 100);

        address[] memory tokens = wberaHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(ORI_BGT));
        assertEq(tokens[1], address(OTHER_REWARD_TOKEN));

        (
            address rewardsDistributor,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        ) = wberaHoneyAutoStaking.rewardData(address(OTHER_REWARD_TOKEN));
        assertEq(rewardsDistributor, address(0));
        assertEq(rewardsDuration, 30 days);
        assertEq(periodFinish, 0);
        assertEq(rewardRate, 0);
        assertEq(lastUpdateTime, 0);
        assertEq(rewardPerTokenStored, 0);
        assertEq(rewardResidual, 0);
    }

    function test_removeReward_revertInvalidToken() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.RewardDoesntExist.selector));
        wberaHoneyAutoStaking.removeReward(address(0));
    }

    function test_removeReward_revertPrimaryToken() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(ORI_BGT)));
        wberaHoneyAutoStaking.removeReward(address(ORI_BGT));
    }

    function test_removeReward_rewardDoesntExist() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.RewardDoesntExist.selector));
        wberaHoneyAutoStaking.removeReward(address(WBERA));
    }

    function test_removeReward_periodNotFinished() public {
        vm.startPrank(origamiMultisig);
        DummyMintableToken randomToken = new DummyMintableToken(origamiMultisig, "Random Token", "RND", 18);
        wberaHoneyAutoStaking.addReward(address(randomToken), 30 days, 100);
        deal(address(randomToken), origamiMultisig, 100e18);
        randomToken.approve(address(wberaHoneyAutoStaking), 100e18);
        wberaHoneyAutoStaking.notifyRewardAmount(address(randomToken), 100e18);

        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.PeriodNotFinished.selector));
        wberaHoneyAutoStaking.removeReward(address(randomToken));
    }

    function test_removeReward_success() public {
        vm.startPrank(origamiMultisig);
        DummyMintableToken OTHER_REWARD_TOKEN2 = new DummyMintableToken(origamiMultisig, "REWARD2", "REWARD2", 18);

        wberaHoneyAutoStaking.addReward(address(WBERA), 7 days, 100);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 7 days, 100);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN2), 7 days, 100);
        address[] memory tokens = wberaHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 4);
        assertEq(tokens[0], address(ORI_BGT));
        assertEq(tokens[1], address(WBERA));
        assertEq(tokens[2], address(OTHER_REWARD_TOKEN));
        assertEq(tokens[3], address(OTHER_REWARD_TOKEN2));

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardRemoved(address(WBERA));
        wberaHoneyAutoStaking.removeReward(address(WBERA));

        // It gets flipped from the swap and pop
        tokens = wberaHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], address(ORI_BGT));
        assertEq(tokens[1], address(OTHER_REWARD_TOKEN2));
        assertEq(tokens[2], address(OTHER_REWARD_TOKEN));
    }

    function test_addReward_afterRemovingAndRecovering() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        // Add and notify for some other reward amount
        vm.startPrank(origamiMultisig);
        uint256 rewardsAmount = 100e18;
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 1 days, 100);
        deal(address(OTHER_REWARD_TOKEN), origamiMultisig, rewardsAmount);
        OTHER_REWARD_TOKEN.approve(address(wberaHoneyAutoStaking), rewardsAmount);
        wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), rewardsAmount);
        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(OTHER_REWARD_TOKEN)), 99e18);

        // Remove and recover that other reward amount
        skip(1 days);
        wberaHoneyAutoStaking.removeReward(address(OTHER_REWARD_TOKEN));
        address[] memory tokens = wberaHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 1);
        wberaHoneyAutoStaking.recoverToken(address(OTHER_REWARD_TOKEN), origamiMultisig, 99e18);
        assertEq(OTHER_REWARD_TOKEN.balanceOf(origamiMultisig), 99e18);
        
        // Can't be added again until there's enough balance to cover the previous unclaimed rewards
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(OTHER_REWARD_TOKEN), 99e18));
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 1 days, 100);
        OTHER_REWARD_TOKEN.transfer(address(wberaHoneyAutoStaking), 99e18);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardStored(address(OTHER_REWARD_TOKEN), 1 days);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 1 days, 100);
        tokens = wberaHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 2);
    }

    function test_setSwapper_success() public {
        assertEq(wberaHoneyAutoStaking.swapper(), address(0));
        assertEq(wberaHoneyAutoStaking.isMultiRewardMode(), true);
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.SwapperSet(alice);
        wberaHoneyAutoStaking.setSwapper(alice);
        assertEq(wberaHoneyAutoStaking.swapper(), alice);
        assertEq(wberaHoneyAutoStaking.isMultiRewardMode(), false);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.SwapperSet(address(0));
        wberaHoneyAutoStaking.setSwapper(address(0));
        assertEq(wberaHoneyAutoStaking.swapper(), address(0));
        assertEq(wberaHoneyAutoStaking.isMultiRewardMode(), true);
    }

    function test_setRestrictedPublicHarvest_success() public {
        assertEq(wberaHoneyAutoStaking.restrictedPublicHarvest(), false);
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.RestrictedPublicHarvestSet(true);
        wberaHoneyAutoStaking.setRestrictedPublicHarvest(true);
        assertEq(wberaHoneyAutoStaking.restrictedPublicHarvest(), true);
    }

    function test_setPostProcessingDisabled_success() public {
        assertEq(wberaHoneyAutoStaking.postProcessingDisabled(), false);
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.PostProcessingDisabledSet(true);
        wberaHoneyAutoStaking.setPostProcessingDisabled(true);
        assertEq(wberaHoneyAutoStaking.postProcessingDisabled(), true);
    }

    function test_setPaused_success() public {
        (bool onStake_, bool onWithdraw_, bool onGetReward_) = wberaHoneyAutoStaking.isPaused();
        assertFalse(onStake_);
        assertFalse(onWithdraw_);
        assertFalse(onGetReward_);
        
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.PausedSet(true, true, true);
        wberaHoneyAutoStaking.setPaused(true, true, true);

        (onStake_, onWithdraw_, onGetReward_) = wberaHoneyAutoStaking.isPaused();
        assertTrue(onStake_);
        assertTrue(onWithdraw_);
        assertTrue(onGetReward_);
    }

    function test_recoverToken_success() public {
        uint256 amount = 100 ether;
        DummyMintableToken token = new DummyMintableToken(origamiMultisig, "fake", "fake", 18);

        vm.startPrank(origamiMultisig);
        token.addMinter(origamiMultisig);
        token.mint(address(wberaHoneyAutoStaking), amount);

        vm.expectEmit();
        emit IMultiRewards.Recovered(address(token), amount);
        wberaHoneyAutoStaking.recoverToken(address(token), alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(wberaHoneyAutoStaking)), 0);
    }

    function test_recoverToken_canRecoverStakingToken() public {
        uint256 stakeAmount = 100e18;
        deal(address(WBERA), address(wberaHoneyAutoStaking), stakeAmount);

        // check cannot recover staking token
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.recoverToken(address(WBERA), alice, stakeAmount);
        vm.stopPrank();
    }

    function test_recoverToken_revertWithTokenReward() public {
        // Setup reward token in the wberaHoneyAutoStaking and mint rewards
        vm.startPrank(origamiMultisig);
        uint256 rewardsAmount = 100e18;
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 86400, 100);

        deal(address(ORI_BGT), origamiMultisig, rewardsAmount);
        ORI_BGT.approve(address(wberaHoneyAutoStaking), rewardsAmount);
        wberaHoneyAutoStaking.notifyRewardAmount(address(ORI_BGT), rewardsAmount);

        // check cannot recover reward token
        (,,,, uint256 lastUpdateTime,,) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertNotEq(lastUpdateTime, 0);

        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.CannotRecoverRewardToken.selector));
        wberaHoneyAutoStaking.recoverToken(address(ORI_BGT), alice, rewardsAmount);
    }

    function test_setPerformanceFees_invalidFee() public {
        vm.startPrank(origamiMultisig);
        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](1);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 101);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        wberaHoneyAutoStaking.setPerformanceFees(fees);

        fees = new IOrigamiAutoStaking.TokenAndAmount[](2);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 99);
        fees[1] = IOrigamiAutoStaking.TokenAndAmount(address(HONEY), 101);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        wberaHoneyAutoStaking.setPerformanceFees(fees);
    }

    function test_setPerformanceFees_primary_claimExistingFees() public {
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);
        vm.startPrank(origamiMultisig);

        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0);

        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](1);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 0);
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.PerformanceFeesSet(address(ORI_BGT), 0);
        wberaHoneyAutoStaking.setPerformanceFees(fees);
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 0);
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0.000019529055948494e18);
    }

    function test_setPerformanceFees_multi_claimExistingFees() public {
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(HONEY)), 0);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);
        vm.startPrank(origamiMultisig);

        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0);

        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](2);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 0);
        fees[1] = IOrigamiAutoStaking.TokenAndAmount(address(HONEY), 99);

        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.PerformanceFeesSet(address(ORI_BGT), 0);
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.PerformanceFeesSet(address(HONEY), 99);
        wberaHoneyAutoStaking.setPerformanceFees(fees);
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 0);
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(HONEY)), 99);
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0.000019529055948494e18);
    }

    function test_setFeeCollector_invalidFeeCollector() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        wberaHoneyAutoStaking.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IOrigamiAutoStaking.FeeCollectorSet(alice);
        wberaHoneyAutoStaking.setFeeCollector(alice);
        assertEq(wberaHoneyAutoStaking.feeCollector(), alice,"Fee collector is set");
    }

    function test_updateRewardsDuration_success() public {
        uint256 newDuration = 7 days;

        vm.startPrank(origamiMultisig);
        vm.expectEmit();
        emit IMultiRewards.RewardsDurationUpdated(address(ORI_BGT), newDuration);
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), newDuration);
        vm.stopPrank();

        // Verify that the rewards duration was updated correctly
        (, uint256 actualDuration,,,,,) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertEq(
            actualDuration,
            newDuration,
            "Rewards duration not updated correctly"
        );
    }

    function test_updateRewardsDuration_withLeftovers() public {
        uint256 newDuration = 7 days;
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(5 minutes);
        wberaHoneyAutoStaking.harvestVault();

        vm.startPrank(alice);
        wberaHoneyAutoStaking.getReward();

        skip(7 minutes);
        wberaHoneyAutoStaking.harvestVault();

        vm.startPrank(origamiMultisig);
        vm.expectEmit();
        emit IMultiRewards.RewardsDurationUpdated(address(ORI_BGT), newDuration);
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), newDuration);
        vm.stopPrank();

        // Verify that the rewards duration was updated correctly
        (
            ,
            uint256 rewardsDuration,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
            uint256 rewardResidual
        ) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertEq(rewardsDuration, newDuration);
        assertEq(periodFinish, 1744052344);
        assertEq(rewardRate, 451634831);
        assertEq(lastUpdateTime, 1743447544);
        assertEq(rewardPerTokenStored, 1127802981022);
        assertEq(rewardResidual, 105450);
    }

    function test_updateRewardsDuration_revertRewardDoesntExist() public {
        uint256 newDuration = 7 days;

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.RewardDoesntExist.selector));
        wberaHoneyAutoStaking.updateRewardsDuration(address(OTHER_REWARD_TOKEN), newDuration);
    }

     function testRevertWithZeroDurationUpdateRewardsDuration() public {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 1 days, 100); // Setup reward token
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), 0);
        vm.stopPrank();
    }
}

contract OrigamiAutoStakingToErc4626Test_StakeWithdraw is OrigamiAutoStakingToErc4626TestBase {
    function test_stake_success() public {
        uint256 stakeAmount = 100e18;
        deal(alice, stakeAmount);
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, stakeAmount);

        // User approves the infraredVault to spend their tokens
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), stakeAmount);

        // check stake event emitted
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IMultiRewards.Staked(alice, stakeAmount);
        // User stakes tokens into the infraredVault
        wberaHoneyAutoStaking.stake(stakeAmount);

        // Check user's balance in the infraredVault
        uint256 userBalance = wberaHoneyAutoStaking.balanceOf(alice);
        assertEq(userBalance, stakeAmount, "User balance should be updated");

        // Check total supply in the infraredVault
        uint256 totalSupply = wberaHoneyAutoStaking.totalSupply() - 1; // infared holds a balance of 1 wei in every vault
        assertEq(totalSupply, stakeAmount, "Total supply should be updated");

        // Check staking token staked in infrared vault
        assertEq(IR_WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), stakeAmount);
        assertEq(WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(WBERA_HONEY.balanceOf(alice), 0);

        vm.stopPrank();
    }

    function test_stake_revertWithZeroAmount() public {
        deal(address(WBERA_HONEY), alice, 0);
        vm.startPrank(alice);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 0);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        wberaHoneyAutoStaking.stake(0);
        vm.stopPrank();
    }

    function test_stake_revertMoreThanUsersBalance() public {
        uint256 stakeAmount = 2000e18; // More than user's balance

        deal(address(WBERA_HONEY), alice, stakeAmount - 1000e18);
        vm.startPrank(alice);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), stakeAmount);

        vm.expectRevert("BAL#416"); // Expect revert due to insufficient balance
        wberaHoneyAutoStaking.stake(stakeAmount);
        vm.stopPrank();
    }

    function test_withdraw_success() public {
        uint256 amount = 500e18;
        vm.startPrank(bob);
        deal(address(WBERA_HONEY), bob, amount);
        // User stakes tokens
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), amount);
        wberaHoneyAutoStaking.stake(amount);
        vm.stopPrank();

        uint256 withdrawAmount = amount;

        // check withdrawn event emitted
        vm.expectEmit();
        emit IMultiRewards.Withdrawn(bob, withdrawAmount);

        vm.startPrank(bob);
        wberaHoneyAutoStaking.withdraw(withdrawAmount);
        vm.stopPrank();

        // Check user's balance in the infraredVault after withdrawal
        uint256 userBalance = wberaHoneyAutoStaking.balanceOf(bob);
        assertEq(
            userBalance, 0, "User balance should decrease after withdrawal"
        );

        // Check total supply in the infraredVault after withdrawal
        uint256 totalSupply = wberaHoneyAutoStaking.totalSupply() - 1; // infared holds a balance of 1 wei in every vault
        assertEq(
            totalSupply, 0, "Total supply should decrease after withdrawal"
        );

        // Check user's token balance
        uint256 userTokenBalance = WBERA_HONEY.balanceOf(bob);
        assertEq(
            userTokenBalance,
            amount,
            "User should receive the withdrawn tokens"
        );
    }

    function test_withdraw_revertMoreThanStaked() public {
        // User stakes tokens
        deal(bob, 500e18);
        vm.startPrank(bob);
         deal(address(WBERA_HONEY), bob, 500e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 500e18);
        wberaHoneyAutoStaking.stake(500e18);
        vm.stopPrank();

        uint256 withdrawAmount = 600e18; // More than staked amount

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(WBERA_HONEY), withdrawAmount));
        wberaHoneyAutoStaking.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    function test_withdraw_revertZeroAmount() public {
        // User stakes tokens
        deal(bob, 500e18);
        vm.startPrank(bob);
        deal(address(WBERA_HONEY), bob, 500e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 500e18);
        wberaHoneyAutoStaking.stake(500e18);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        wberaHoneyAutoStaking.withdraw(0);
        vm.stopPrank();
    }

    function test_withdraw_revertAsDifferentUser() public {
        // User stakes tokens
        deal(bob, 500e18);
        vm.startPrank(bob);
        deal(address(WBERA_HONEY), bob, 500e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 500e18);
        wberaHoneyAutoStaking.stake(500e18);
        vm.stopPrank();

        address otherUser = address(6);
        uint256 withdrawAmount = 100e18;

        vm.startPrank(otherUser);
        // Assuming otherUser hasn't staked anything
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAmount.selector, address(WBERA_HONEY), withdrawAmount));
        wberaHoneyAutoStaking.withdraw(withdrawAmount);
        vm.stopPrank();
    }
}

contract OrigamiAutoStakingToErc4626Test_MultiAssetMode is OrigamiAutoStakingToErc4626TestBase {

    function test_harvestVault_primary_withFees() public virtual {
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);
        vm.startPrank(origamiMultisig);

        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0);
        wberaHoneyAutoStaking.harvestVault();
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0.000019529055948494e18);
    }

    function test_harvestVault_primary_noFees() public virtual {
        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](1);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 0);
        vm.prank(origamiMultisig);
        wberaHoneyAutoStaking.setPerformanceFees(fees);

        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 0);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);
        vm.startPrank(origamiMultisig);

        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0);
        wberaHoneyAutoStaking.harvestVault();
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001952905594849359e18);
        assertEq(ORI_BGT.balanceOf(feeCollector), 0);
    }

    function test_harvestVault_success() public virtual {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        assertEq(wberaHoneyAutoStaking.earned(alice, address(ORI_BGT)), 0);

        uint256 rewardAmount = 1000e18;
        IOrigamiAutoStaking.TokenAndAmount[] memory fees = new IOrigamiAutoStaking.TokenAndAmount[](1);
        fees[0] = IOrigamiAutoStaking.TokenAndAmount(address(ORI_BGT), 0);
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPerformanceFees(fees);
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), 1 days);
        deal(address(IBGT), address(wberaHoneyAutoStaking), rewardAmount);
        rewardAmount = ORI_BGT.previewDeposit(rewardAmount);

        uint256 residual = rewardAmount % 1 days;
        vm.expectEmit(address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardAdded(address(ORI_BGT), rewardAmount - residual);
        // Calling harvest vault also notifies reward
        wberaHoneyAutoStaking.harvestVault();
        assertEq(wberaHoneyAutoStaking.totalSupply(), 100e18 + 1);
        assertEq(wberaHoneyAutoStaking.earned(alice, address(ORI_BGT)), 0);

        // Alice gets basically all of the rewards
        skip(3 days);
        assertApproxEqAbs(wberaHoneyAutoStaking.earned(alice, address(ORI_BGT)), rewardAmount - residual, tolerance);
    }

    function test_harvestVault_successfulNotification() public virtual {
        uint256 rewardAmount = 1000e18;
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), 30 days);
        deal(address(IBGT), address(wberaHoneyAutoStaking), rewardAmount);
        rewardAmount = ORI_BGT.previewDeposit(rewardAmount);

        uint256 residual = rewardAmount % 30 days;
        uint256 actualOribgtAdded = 947.493620815309056000e18; // doesn't include the residual
        assertApproxEqAbs(
            (rewardAmount - residual)*99/100, // 1% fee
            actualOribgtAdded, // Slightly different due to rounding
            1e7
        );
        vm.expectEmit(true, true, true, true, address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardAdded(address(ORI_BGT), actualOribgtAdded);
        wberaHoneyAutoStaking.harvestVault();

        (
            ,
            ,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
        ) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertGt(periodFinish, vm.getBlockTimestamp(), "Reward notification failed");
        // check reward data updated on notify
        assertApproxEqAbs(rewardRate, rewardAmount * 99/100 / (30 days), tolerance); // 1% fee
        assertEq(lastUpdateTime, vm.getBlockTimestamp());
        assertEq(periodFinish, vm.getBlockTimestamp() + 30 days);
        assertEq(rewardPerTokenStored, 0);
        // check balance transfer
        assertApproxEqAbs(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), rewardAmount*99/100, tolerance); // 1% fee
        assertEq(ORI_BGT.balanceOf(origamiMultisig), 0);
        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), rewardAmount*99/100);
    }

    function test_anonUserClaimsViaInfrared() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);

        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(wberaHoneyAutoStaking.unharvestedRewards(address(IBGT)), 0.002040521969010900e18);
        IR_WBERA_HONEY.getRewardForUser(address(wberaHoneyAutoStaking));
        uint256 ibgtEarned = IBGT.balanceOf(address(wberaHoneyAutoStaking));
        assertEq(ibgtEarned, 0.002040521969010900e18);
        uint256 shares = getOriSharesAfterDeposit(ibgtEarned);
        assertEq(shares, 0.001952905594849359e18);

        // Now harvest the vault 
        assertEq(wberaHoneyAutoStaking.unharvestedRewards(address(IBGT)), 0);
        wberaHoneyAutoStaking.harvestVault();
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertApproxEqAbs(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), shares*99/100, tolerance);
    }

    function test_getRewardForUser_failure() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.135668134542432732e18);
        uint256 earned = wberaHoneyAutoStaking.earned(alice, address(ORI_BGT));
        assertEq(earned, 0.001933376538900500e18);

        // Deal one less than earned - that just gets skipped
        deal(address(ORI_BGT), address(wberaHoneyAutoStaking), earned-1, true);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), earned-1);
        wberaHoneyAutoStaking.getRewardForUser(alice);
        assertEq(ORI_BGT.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        notifyRewardAmount
    //////////////////////////////////////////////////////////////*/

    function test_notifyRewardAmount_primaryBoostedRewards() public virtual {
        uint256 rewardAmount = 1000e18;
        uint256 boostedAmount = 100e18;
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.updateRewardsDuration(address(ORI_BGT), 30 days);
        deal(address(IBGT), address(wberaHoneyAutoStaking), rewardAmount);
        deal(address(ORI_BGT), origamiMultisig, boostedAmount);
        rewardAmount = ORI_BGT.previewDeposit(rewardAmount);
        rewardAmount += boostedAmount;

        // approve boosted amount
        IERC20(ORI_BGT).approve(address(wberaHoneyAutoStaking), boostedAmount);

        uint256 residual = rewardAmount % 30 days;
        uint256 actualOribgtAdded = 1_046.493620815310496000e18;
        assertApproxEqAbs(
            (rewardAmount - residual)*99/100, // 1% fee
            actualOribgtAdded, // Slightly different due to rounding
            1e7
        );
        vm.expectEmit(true, true, true, true, address(wberaHoneyAutoStaking));
        emit IMultiRewards.RewardAdded(address(ORI_BGT), actualOribgtAdded);

        wberaHoneyAutoStaking.notifyRewardAmount(address(ORI_BGT), boostedAmount);

        (
            ,
            ,
            uint256 periodFinish,
            uint256 rewardRate,
            uint256 lastUpdateTime,
            uint256 rewardPerTokenStored,
        ) = wberaHoneyAutoStaking.rewardData(address(ORI_BGT));
        assertGt(periodFinish, vm.getBlockTimestamp(), "Reward notification failed");

        // check reward data updated on notify
        assertApproxEqAbs(rewardRate, rewardAmount * 99/100 / (30 days), tolerance); // 1% fee
        assertEq(lastUpdateTime, vm.getBlockTimestamp());
        assertEq(periodFinish, vm.getBlockTimestamp() + 30 days);
        assertEq(rewardPerTokenStored, 0);

        // check balance transfer
        assertApproxEqAbs(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), rewardAmount * 99/100, tolerance); // 1% fee
        assertEq(ORI_BGT.balanceOf(origamiMultisig), 0);
        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), rewardAmount * 99/100);
    }

    function test_notifyRewardAmount_revertNotRewardToken() public virtual {
        uint256 rewardAmount = 1000e18;

        vm.startPrank(origamiMultisig);
        deal(address(OTHER_REWARD_TOKEN), origamiMultisig, rewardAmount);
        OTHER_REWARD_TOKEN.approve(address(wberaHoneyAutoStaking), rewardAmount);
        vm.expectRevert(abi.encodeWithSelector(IMultiRewards.RewardDoesntExist.selector));
        wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), rewardAmount);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_revertWithZeroAmount() public virtual {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.addReward(address(OTHER_REWARD_TOKEN), 30 days, 100);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), 0);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_boostedPrimaryRewards() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        uint256 boostAmount = 100e18;

        uint256 oribgtTotalSupply = ORI_BGT.totalSupply();
        assertEq(oribgtTotalSupply, 1_411_172.742655615111698872e18);

        // Pass time to earn some ibgt rewards
        skip(3 days);
        uint256 vaultBalance = ORI_BGT.balanceOf(address(wberaHoneyAutoStaking));
        assertEq(vaultBalance, 0);
        uint256 ibgtEarned = IMultiRewards(IR_WBERA_HONEY).earned(address(wberaHoneyAutoStaking), address(IBGT));
        assertEq(ibgtEarned, 0.002040521969010900e18);
        uint256 shares = getOriSharesAfterDeposit(ibgtEarned);
        assertEq(shares, 0.001952905594849359e18);

        // claim ibgt rewards and stake into oribgt. distribute oribgt shares as rewards
        vm.startPrank(origamiMultisig);
        deal(address(ORI_BGT), origamiMultisig, boostAmount);
        ORI_BGT.approve(address(wberaHoneyAutoStaking), boostAmount);
        wberaHoneyAutoStaking.notifyRewardAmount(address(ORI_BGT), boostAmount);
        uint256 newVaultBalance = ORI_BGT.balanceOf(address(wberaHoneyAutoStaking));
        uint256 newOribgtTotalSupply = ORI_BGT.totalSupply();

        // Assertions
        assertEq(newVaultBalance, 99.001933376538900865e18, "OriBGT balance of vault should increase");
        assertEq(newOribgtTotalSupply, 1_411_172.744608520706548231e18, "OriBGT total supply should increase");
        assertEq(wberaHoneyAutoStaking.performanceFeeBps(address(ORI_BGT)), 100);
        assertEq(
            (shares+boostAmount)*99/100, // 1% fee
            newVaultBalance,
            "Vault OriBGT balance"
        );
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        getReward
    //////////////////////////////////////////////////////////////*/

    function test_getReward_primaryOnlySuccess() public virtual {
        uint256 rewardsAmount = 100e18;
        uint256 rewardsDuration = 30 days;
        rewardsAmount = setUpGetReward(rewardsAmount, rewardsDuration);

        vm.startPrank(alice);
        // Manipulate time to simulate the passage of the reward duration
        skip(rewardsDuration + 100 minutes);
        wberaHoneyAutoStaking.getReward();

        vm.stopPrank();

        // Check user's rewards token balance
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            rewardsAmount*99/100, // 1% fee
            tolerance,
            "User should receive the rewards within tolerance"
        );
        assertEq(OTHER_REWARD_TOKEN.balanceOf(alice), 0);
    }

    function test_getReward_noRewardsSuccess() public virtual {
        uint256 rewardsAmount = 100e18;
        uint256 rewardsDuration = 30 days;
        setUpGetReward(rewardsAmount, rewardsDuration);

        address otherUser = makeAddr("otherUser");

        // Simulate another user who hasn't earned any rewards
        vm.startPrank(otherUser);
        wberaHoneyAutoStaking.getReward();
        vm.stopPrank();

        // Check other user's rewards token balance
        uint256 otherUserRewardsBalance = ORI_BGT.balanceOf(otherUser);
        assertEq(otherUserRewardsBalance, 0, "User should not receive any rewards");
        assertEq(OTHER_REWARD_TOKEN.balanceOf(otherUser), 0);
    }

    function test_getReward_twiceSuccess() public virtual {
        uint256 rewardsAmount = 100e18;
        uint256 rewardsDuration = 30 days;
        rewardsAmount = setUpGetReward(rewardsAmount, rewardsDuration);

        // Claim rewards twice
        vm.startPrank(alice);
        skip(rewardsDuration + 1 minutes / 2); // Simulate half the reward duration
        wberaHoneyAutoStaking.getReward();

        skip(rewardsDuration + 1 minutes / 2); // Complete the reward duration
        wberaHoneyAutoStaking.getReward();

        // Check user's rewards token balance after second claim
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            rewardsAmount*99/100, // 1% fee
            tolerance,
            "User should receive the full rewards within tolerance after second claim"
        );
        assertEq(OTHER_REWARD_TOKEN.balanceOf(alice), 0);
    }

    function test_getReward_multipleRewardTokens() public virtual {
        uint256 rewardsDuration = 30 days;
        uint256 firstRewardAmount = setUpGetReward(50e18 /* iBGT */, rewardsDuration);

        // Notify rewards for both tokens
        uint256 secondRewardAmount = 75e18;
        {
            vm.startPrank(origamiMultisig);
            OTHER_REWARD_TOKEN.mint(origamiMultisig, secondRewardAmount);
            OTHER_REWARD_TOKEN.approve(address(wberaHoneyAutoStaking), secondRewardAmount);
            wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), secondRewardAmount);
            vm.stopPrank();
        }

        // Skip time to ensure rewards are distributed
        skip(rewardsDuration + 100 minutes);

        // User claims rewards
        vm.prank(alice);
        wberaHoneyAutoStaking.getReward();

        // Check user received rewards for both tokens
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            firstRewardAmount*99/100, // 1% fee
            tolerance,
            "Incorrect first reward amount"
        );
        assertApproxEqAbs(
            OTHER_REWARD_TOKEN.balanceOf(alice),
            secondRewardAmount*995/1000, // 0.5% fee
            tolerance,
            "Incorrect second reward amount"
        );
    }

    function test_getRewardForUser_success_normal() public virtual {
        uint256 rewardsDuration = 30 days;
        uint256 rewardsAmount = setUpGetReward(100e18, rewardsDuration);

        // Manipulate time to simulate the passage of the reward duration
        skip(rewardsDuration + 100 minutes);
        wberaHoneyAutoStaking.getRewardForUser(alice);

        // Check user's rewards token balance
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            rewardsAmount*99/100, // 1% fee
            tolerance,
            "User should receive the rewards within tolerance"
        );
        assertEq(OTHER_REWARD_TOKEN.balanceOf(alice), 0);
    }

    function test_getRewardForUser_success_usdt() public virtual {
        stakeOnBehalfOf(ohmHoneyAutoStaking, address(OHM_HONEY), alice, 100e18);

        AnnoyingToken usdt = new AnnoyingToken();
        {
            address infrared = IR_OHM_HONEY.infrared();
            vm.startPrank(infrared);
            IR_OHM_HONEY.addReward(address(usdt), 1 days);
            deal(address(usdt), infrared, 100e18);
            usdt.approve(address(IR_OHM_HONEY), 100e18);
            IR_OHM_HONEY.notifyRewardAmount(address(usdt), 100e18);
            vm.stopPrank();
        }

        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.addReward(address(usdt), 1 days, 100);

        skip(1 days);
        ohmHoneyAutoStaking.harvestVault();
        skip(1 days);

        assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 138.311812904077418300e18);
        assertEq(ohmHoneyAutoStaking.earned(alice, address(usdt)), 17.553031185108239900e18);
        ohmHoneyAutoStaking.getRewardForUser(alice);
        assertEq(ORI_BGT.balanceOf(alice), 138.311812904077418300e18);
        assertEq(usdt.balanceOf(alice), 17.553031185108239900e18);
    }

    function test_rewardTokenIsStakingToken() public {
        stakeOnBehalfOf(ohmHoneyAutoStaking, address(OHM_HONEY), alice, 100e18);

        {
            address infrared = IR_OHM_HONEY.infrared();
            vm.startPrank(infrared);
            IR_OHM_HONEY.addReward(address(OHM_HONEY), 1 days);
            deal(address(OHM_HONEY), infrared, 100e18);
            OHM_HONEY.approve(address(IR_OHM_HONEY), 100e18);
            IR_OHM_HONEY.notifyRewardAmount(address(OHM_HONEY), 100e18);
            vm.stopPrank();
        }

        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.addReward(address(OHM_HONEY), 1 days, 100);

        skip(1 days);
        ohmHoneyAutoStaking.harvestVault();
        skip(1 days);

        assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 138.311812904077418300e18);
        assertEq(ohmHoneyAutoStaking.earned(alice, address(OHM_HONEY)), 17.553031185108239900e18);
        ohmHoneyAutoStaking.getRewardForUser(alice);
        assertEq(ORI_BGT.balanceOf(alice), 138.311812904077418300e18);
        assertEq(OHM_HONEY.balanceOf(alice), 17.553031185108239900e18);
    }
}

contract OrigamiAutoStakingToErc4626Test_SingleAssetMode is OrigamiAutoStakingToErc4626Test_MultiAssetMode {
    function setUp() public override {
        super.setUp();

        vm.prank(origamiMultisig);
        wberaHoneyAutoStaking.setSwapper(address(swapper));
    }

    function test_getReward_multipleRewardTokens() public override {
        uint256 rewardsDuration = 30 days;
        uint256 firstRewardAmount = setUpGetReward(50e18 /* iBGT */, rewardsDuration);

        // Notify rewards for the 'other' reward token
        uint256 secondRewardAmount = 75e18;
        {
            vm.startPrank(origamiMultisig);
            OTHER_REWARD_TOKEN.mint(origamiMultisig, secondRewardAmount);
            OTHER_REWARD_TOKEN.approve(address(wberaHoneyAutoStaking), secondRewardAmount);
            wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), secondRewardAmount);
            vm.stopPrank();
        }

        // Skip time to ensure rewards are distributed
        skip(rewardsDuration + 100 minutes);

        // User claims rewards
        vm.prank(alice);
        wberaHoneyAutoStaking.getReward();

        // Check user received rewards for only the pricipal token
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            firstRewardAmount*99/100, // 1% fee
            tolerance,
            "Incorrect first reward amount"
        );
        assertEq(OTHER_REWARD_TOKEN.balanceOf(alice), 0);

        // Swapper gets the other reward token
        assertEq(OTHER_REWARD_TOKEN.balanceOf(address(swapper)), secondRewardAmount);
    }

    function encodeSwap(
        address callbackHandler,
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 sellAmount,
        uint256 buyTokenAmount,
        uint256 minBuyAmount
    ) internal view returns (bytes memory) {
        return abi.encode(IOrigamiSwapper.RouteDataWithCallback({
            minBuyAmount: minBuyAmount,
            router: address(router),
            receiver: callbackHandler,
            data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(sellToken), sellAmount, address(buyToken), buyTokenAmount))
        }));
    }

    function test_swapCallback_success() public {
        uint256 rewardsDuration = 1 days;
        uint256 firstRewardAmount = setUpGetReward(50e18 /* iBGT */, rewardsDuration);
        assertEq(firstRewardAmount, 47.853213172490451944e18);

        // Notify rewards for the 'other' reward token
        vm.startPrank(origamiMultisig);
        uint256 secondRewardAmount = 75e18;
        {
            OTHER_REWARD_TOKEN.mint(origamiMultisig, secondRewardAmount);
            OTHER_REWARD_TOKEN.approve(address(wberaHoneyAutoStaking), secondRewardAmount);
            wberaHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), secondRewardAmount);
        }

        // Execute on the swapper
        uint256 expectedOriBgtAmount;
        {
            uint256 sellAmount = OTHER_REWARD_TOKEN.balanceOf(address(swapper));
            assertEq(sellAmount, secondRewardAmount);
            uint256 buyAmount = sellAmount;
            expectedOriBgtAmount = ORI_BGT.previewDeposit(buyAmount);
            uint256 buyIbgtAmount = swapper.execute(
                OTHER_REWARD_TOKEN,
                OTHER_REWARD_TOKEN.balanceOf(address(swapper)),
                IBGT,
                encodeSwap(
                    address(wberaHoneyAutoStaking),
                    OTHER_REWARD_TOKEN,
                    IBGT,
                    sellAmount,
                    buyAmount,
                    buyAmount
                )
            );
            assertEq(buyIbgtAmount, buyAmount);
        }
        vm.stopPrank();

        // Skip time to ensure rewards are distributed
        skip(rewardsDuration + 2 days);

        // User claims rewards
        vm.prank(alice);
        wberaHoneyAutoStaking.getReward();

        // Check user received rewards for only the pricipal token
        assertApproxEqAbs(
            ORI_BGT.balanceOf(alice),
            (expectedOriBgtAmount + firstRewardAmount) * 99/100,
            0.01e18
        );
        assertEq(OTHER_REWARD_TOKEN.balanceOf(alice), 0);

        // Swapper doesn't have anything left
        assertEq(OTHER_REWARD_TOKEN.balanceOf(address(swapper)), 0);
        assertEq(IBGT.balanceOf(address(swapper)), 0);
    }

    function notifyReward(DummyMintableToken rewardToken, uint256 amount) private {
        vm.startPrank(origamiMultisig);
        deal(address(rewardToken), origamiMultisig, amount);
        rewardToken.approve(address(ohmHoneyAutoStaking), amount);
        ohmHoneyAutoStaking.notifyRewardAmount(address(rewardToken), amount);
        vm.stopPrank();
    }

    function executeSwap(IERC20 rewardToken) private {
        // Just execute 1:1
        vm.startPrank(origamiMultisig);
        swapper.execute(
            rewardToken,
            rewardToken.balanceOf(address(swapper)),
            IBGT,
            encodeSwap(
                address(ohmHoneyAutoStaking),
                rewardToken,
                IBGT,
                rewardToken.balanceOf(address(swapper)),
                rewardToken.balanceOf(address(swapper)),
                rewardToken.balanceOf(address(swapper))
            )
        );
    }

    // A more complex test switching back and forth between single and multi reward mode
    function test_toggleMode() public {
        // Starts in single mode as there's a swapper set already
        // 3 tokens in total then.
        DummyMintableToken rewardToken1 = new DummyMintableToken(origamiMultisig, "Reward1", "RWD1", 18);
        vm.label(address(rewardToken1), "RWD1");
        DummyMintableToken rewardToken2 = new DummyMintableToken(origamiMultisig, "Reward2", "RWD2", 18);
        vm.label(address(rewardToken1), "RWD2");

        // Setup
        {
            stakeOnBehalfOf(ohmHoneyAutoStaking, address(OHM_HONEY), alice, 100e18);
            skip(10 minutes);

            vm.startPrank(origamiMultisig);
            ohmHoneyAutoStaking.addReward(address(rewardToken1), 10 minutes, 0);
            ohmHoneyAutoStaking.addReward(address(rewardToken2), 10 minutes, 50);
        }

        assertTrue(ohmHoneyAutoStaking.isMultiRewardMode());

        {
            assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
            assertEq(IBGT.balanceOf(feeCollector), 0);
            assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
            assertEq(ORI_BGT.balanceOf(feeCollector), 0);
            assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 0);
            assertEq(rewardToken1.balanceOf(feeCollector), 0);
            assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 0);
            assertEq(rewardToken2.balanceOf(feeCollector), 0);
        }

        // Notify all 3 rewards and skip half way through
        {
            ohmHoneyAutoStaking.harvestVault();
            notifyReward(rewardToken1, 100e18);
            notifyReward(rewardToken2, 100e18);

            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 23.051968817346236417e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 0.232848169872184207e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 0);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 99.5e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 0.5e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 0);
            }

            skip(5 minutes);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 11.525984408673118100e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 49.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 49.749999999999999800e18);
            ohmHoneyAutoStaking.getRewardForUser(alice);
            assertEq(ORI_BGT.balanceOf(alice), 11.525984408673118100e18);
            assertEq(rewardToken1.balanceOf(alice), 49.999999999999999700e18);
            assertEq(rewardToken2.balanceOf(alice), 49.749999999999999800e18);

            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 23.274343825222669504e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 0.232848169872184207e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.999999999999999700e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 0);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 99.5e18 - 49.749999999999999800e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 0.5e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 0);
            }
        }

        // Switch to single-mode
        {
            vm.startPrank(origamiMultisig);
            ohmHoneyAutoStaking.setSwapper(address(swapper));
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 0);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 0);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 0);

            // Notify some more and skip another 5 mins
            ohmHoneyAutoStaking.harvestVault();
            
            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 23.156860231057173992e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 0.350331764037679719e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.999999999999999700e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 0);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.749999999999999800e18 - 0.5e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 0.5e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 0);
            }

            notifyReward(rewardToken1, 100e18);
            notifyReward(rewardToken2, 100e18);
            skip(5 minutes);

            // New rewards were sent to the swapper rather than notified
            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 23.156860231057173992e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 0.350331764037679719e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.999999999999999700e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 100e18);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.749999999999999800e18 - 0.5e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 0.5e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 100e18);
            }

            // Rewards that have already been notified are still received by the user until
            // the duration of the period
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 11.578430115528586700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 49.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 49.749999999999999800e18);

            skip(5 minutes);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 23.156860231057173500e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 49.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 49.749999999999999800e18);

            // Execute the swaps -- oriBGT increases a lot from the 2x100 new iBGT
            executeSwap(rewardToken1);
            executeSwap(rewardToken2);

            // New rewards were sent to the swapper rather than notified
            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 235.991790880958134193e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 2.500179548380113661e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.999999999999999700e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 0);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 100e18 - 49.749999999999999800e18 - 0.5e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 0.5e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 0);
            }

            skip(10 minutes);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 235.991790880958133400e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 49.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 49.749999999999999800e18);
        }

        // Switch back to multi-mode
        {
            vm.startPrank(origamiMultisig);
            ohmHoneyAutoStaking.setSwapper(address(0));
            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 235.991790880958133400e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 49.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 49.749999999999999800e18);

            // Notify some more and skip another 5 mins
            ohmHoneyAutoStaking.harvestVault();
            notifyReward(rewardToken1, 100e18);
            notifyReward(rewardToken2, 100e18);
            skip(5 minutes);

            {
                assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
                assertEq(IBGT.balanceOf(feeCollector), 0);
                assertEq(IBGT.balanceOf(address(swapper)), 0);
                assertEq(ORI_BGT.balanceOf(address(ohmHoneyAutoStaking)), 259.501320384130298598e18);
                assertEq(ORI_BGT.balanceOf(feeCollector), 2.737649543361650676e18);
                assertEq(ORI_BGT.balanceOf(address(swapper)), 0);
                assertEq(rewardToken1.balanceOf(address(ohmHoneyAutoStaking)), 100e18 + 100e18 - 49.999999999999999700e18);
                assertEq(rewardToken1.balanceOf(feeCollector), 0);
                assertEq(rewardToken1.balanceOf(address(swapper)), 0);
                assertEq(rewardToken2.balanceOf(address(ohmHoneyAutoStaking)), 100e18 + 100e18 - 49.749999999999999800e18 - 1e18);
                assertEq(rewardToken2.balanceOf(feeCollector), 1e18);
                assertEq(rewardToken2.balanceOf(address(swapper)), 0);
            }

            assertEq(ohmHoneyAutoStaking.earned(alice, address(ORI_BGT)), 247.746555632544215700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken1)), 99.999999999999999700e18);
            assertEq(ohmHoneyAutoStaking.earned(alice, address(rewardToken2)), 99.499999999999999600e18);

            ohmHoneyAutoStaking.getRewardForUser(alice);
            assertEq(ORI_BGT.balanceOf(alice), 11.525984408673118100e18 + 247.746555632544215700e18);
            assertEq(rewardToken1.balanceOf(alice), 49.999999999999999700e18 + 99.999999999999999700e18);
            assertEq(rewardToken2.balanceOf(alice), 49.749999999999999800e18 + 99.499999999999999600e18);
        }
    }
}

contract OrigamiAutoStakingToErc4626Test_Views is OrigamiAutoStakingToErc4626TestBase {
    function test_getAllRewardTokens() public {
        // Setup: Add multiple reward tokens
        DummyMintableToken rewardToken1 = new DummyMintableToken(origamiMultisig, "Reward1", "RWD1", 18);
        DummyMintableToken rewardToken2 = new DummyMintableToken(origamiMultisig, "Reward2", "RWD2", 18);

        vm.startPrank(origamiMultisig);
        addReward(address(OHM_HONEY), address(rewardToken1), 10 minutes, 0);
        addReward(address(OHM_HONEY), address(rewardToken2), 10 minutes, 50);

        address[] memory allRewards = ohmHoneyAutoStaking.getAllRewardTokens();
        assertEq(allRewards.length, 3);
        assertEq(allRewards[0], address(ORI_BGT));
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(allRewards[0]), 100);
        assertEq(allRewards[1], address(rewardToken1));
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(allRewards[1]), 0);
        assertEq(allRewards[2], address(rewardToken2));
        assertEq(ohmHoneyAutoStaking.performanceFeeBps(allRewards[2]), 50);
    }

    function test_unharvestedRewards_multiRewardsMode_primary() public {
        assertEq(ohmHoneyAutoStaking.unharvestedRewards(address(IBGT)), 0);

        stakeOnBehalfOf(ohmHoneyAutoStaking, address(OHM_HONEY), alice, 100e18);
        assertEq(IBGT.balanceOf(address(ohmHoneyAutoStaking)), 0);
        skip(1 days);
        uint256 earned = IR_OHM_HONEY.earned(address(ohmHoneyAutoStaking), address(IBGT));
        assertEq(ohmHoneyAutoStaking.unharvestedRewards(address(IBGT)), earned);
    }

    function test_unharvestedRewards_multiRewardsMode_other() public {
        stakeOnBehalfOf(ohmHoneyAutoStaking, address(OHM_HONEY), alice, 100e18);

        address infrared = IR_OHM_HONEY.infrared();
        vm.startPrank(infrared);
        IR_OHM_HONEY.addReward(address(OTHER_REWARD_TOKEN), 1 days);
        deal(address(OTHER_REWARD_TOKEN), infrared, 100e18);
        OTHER_REWARD_TOKEN.approve(address(IR_OHM_HONEY), 100e18);
        IR_OHM_HONEY.notifyRewardAmount(address(OTHER_REWARD_TOKEN), 100e18);
        skip(1 days/2);
        
        uint256 underlyingBalance = IR_OHM_HONEY.balanceOf(address(ohmHoneyAutoStaking));
        assertEq(underlyingBalance, 100e18);
        uint256 underlyingTotalSupply = IR_OHM_HONEY.totalSupply();
        assertEq(underlyingTotalSupply, 564.005150768431931108e18);
        
        // Earned proportional rewards for 50% of the period
        uint256 earned = IR_OHM_HONEY.earned(address(ohmHoneyAutoStaking), address(OTHER_REWARD_TOKEN));
        assertApproxEqAbs(earned, underlyingBalance*100e18/underlyingTotalSupply/2, tolerance);
        assertEq(ohmHoneyAutoStaking.unharvestedRewards(address(OTHER_REWARD_TOKEN)), earned);
    }

    function test_getAllRewardsForUser_all() public {
        uint256 stakeAmount = 100e18;
        uint256 rewardAmount = 1000e18;

        vm.startPrank(origamiMultisig);
        addReward(address(OHM_HONEY), address(OTHER_REWARD_TOKEN), 10 minutes, 50);
        address[] memory tokens = ohmHoneyAutoStaking.getAllRewardTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(ORI_BGT));
        assertEq(tokens[1], address(OTHER_REWARD_TOKEN));

        assertEq(ohmHoneyAutoStaking.getRewardForDuration(address(ORI_BGT)), 0);
        assertEq(ohmHoneyAutoStaking.getRewardForDuration(address(OTHER_REWARD_TOKEN)), 0);
        assertEq(ohmHoneyAutoStaking.lastTimeRewardApplicable(address(ORI_BGT)), 0);
        assertEq(ohmHoneyAutoStaking.lastTimeRewardApplicable(address(OTHER_REWARD_TOKEN)), 0);

        // Setup: Give user some OHM_HONEY to stake
        deal(address(OHM_HONEY), bob, stakeAmount);

        // Setup: Add rewards
        deal(address(IBGT), address(ohmHoneyAutoStaking), 100e18);
        ohmHoneyAutoStaking.harvestVault();
        // add oribgt rewards to vault
        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.harvestVault();
        vm.stopPrank();

        // add reward token rewards to vault
        deal(address(OTHER_REWARD_TOKEN), address(origamiMultisig), rewardAmount);
        vm.startPrank(origamiMultisig);
        OTHER_REWARD_TOKEN.approve(address(ohmHoneyAutoStaking), rewardAmount);
        ohmHoneyAutoStaking.notifyRewardAmount(address(OTHER_REWARD_TOKEN), rewardAmount);
        vm.stopPrank();

        // User stakes tokens
        vm.startPrank(bob);
        OHM_HONEY.approve(address(ohmHoneyAutoStaking), stakeAmount);
        ohmHoneyAutoStaking.stake(stakeAmount);
        vm.stopPrank();

        // Simulate passage of time to accrue rewards
        skip(7 days);

        // Get all rewards for user
        IOrigamiAutoStaking.TokenAndAmount[] memory rewards = ohmHoneyAutoStaking.getAllRewardsForUser(bob);
        assertEq(rewards.length, 2, "Should have 2 reward tokens");
        assertEq(rewards[0].amount, 94.749362081531094500e18, "User should have rewards for InfraredBGT");
        assertEq(rewards[0].token, address(ORI_BGT), "User should have rewards for rewardToken");

        assertEq(rewards[1].amount, 994.999999999999999700e18, "User should have rewards for rewardToken");
        assertEq(rewards[1].token, address(OTHER_REWARD_TOKEN), "User should have rewards for rewardToken");

        assertEq(ohmHoneyAutoStaking.getRewardForDuration(address(ORI_BGT)), 94.749362081531094600e18);
        assertEq(ohmHoneyAutoStaking.getRewardForDuration(address(OTHER_REWARD_TOKEN)), 994.999999999999999800e18);
        assertEq(ohmHoneyAutoStaking.lastTimeRewardApplicable(address(ORI_BGT)), 1743447424);
        assertEq(ohmHoneyAutoStaking.lastTimeRewardApplicable(address(OTHER_REWARD_TOKEN)), 1743447424);
    }

    function test_getAllRewardsForUser_onlyOneRewardToken() public {
        test_getAllRewardsForUser_all();

        // stake for alice
        deal(address(OHM_HONEY), alice, 100e18);
        vm.startPrank(alice);
        OHM_HONEY.approve(address(ohmHoneyAutoStaking), 100e18);
        ohmHoneyAutoStaking.stake(100e18);
        vm.stopPrank();

        // add more oriBGT rewards to vault
        deal(address(ORI_BGT), origamiMultisig, 100e18);
        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.harvestVault();
        vm.stopPrank();

        // Simulate passage of time to accrue rewards
        skip(7 days);

        // get rewards for alice
        IOrigamiAutoStaking.TokenAndAmount[] memory user2Rewards = ohmHoneyAutoStaking.getAllRewardsForUser(alice);
        assertEq(user2Rewards.length, 1, "Should have 1 reward token");
        assertEq(user2Rewards[0].amount, 69.155906464191322400e18, "User should have rewards for OriBGT");
        assertEq(user2Rewards[0].token, address(ORI_BGT), "User should have rewards for OriBGT");

        // get rewards for bob and verify amount is greater
        IOrigamiAutoStaking.TokenAndAmount[] memory userRewards = ohmHoneyAutoStaking.getAllRewardsForUser(bob);
        assertEq(userRewards.length, 2, "Should have 2 reward tokens");
        assertEq(userRewards[0].amount, 163.905268545722416900e18, "User should have rewards for OriBGT");
        assertEq(userRewards[0].token, address(ORI_BGT), "User should have rewards for OriBGT");
        assertEq(userRewards[1].amount, 994.999999999999999700e18, "User should have rewards for other rewward token");
        assertEq(userRewards[1].token, address(OTHER_REWARD_TOKEN), "User should have rewards for other rewward token");
    }

    function test_getAllRewardsForUser_withNoStake() public {
        vm.startPrank(origamiMultisig);
        addReward(address(OHM_HONEY), address(OTHER_REWARD_TOKEN), 10 minutes, 50);

        // add ibgt rewards to vault
        deal(address(ORI_BGT), origamiMultisig, 100e18);
        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.harvestVault();
        vm.stopPrank();

        // Get all rewards for user with no stake
        IOrigamiAutoStaking.TokenAndAmount[] memory rewards =
            ohmHoneyAutoStaking.getAllRewardsForUser(bob);

        assertEq(rewards.length, 0);
    }

    function test_rewardPerToken_zeroSupply() public {
        assertEq(ohmHoneyAutoStaking.totalSupply(), 1);
        assertEq(ohmHoneyAutoStaking.rewardPerToken(address(ORI_BGT)), 0);

        vm.startPrank(origamiMultisig);
        vm.expectRevert(stdError.arithmeticError);
        ohmHoneyAutoStaking.withdraw(1);
    }

    function test_rewardPerToken_residualAmountsHandling() public {
        // Setup
        uint256 rewardDuration = 10 minutes;
        DummyMintableToken _stakingToken = DummyMintableToken(address(OHM_HONEY));
        IERC20 rewardsToken = ORI_BGT;

        vm.startPrank(origamiMultisig);
        ohmHoneyAutoStaking.updateRewardsDuration(
            address(rewardsToken), rewardDuration
        );
        vm.stopPrank();

        // User stakes
        uint256 stakingAmount = 1e18;
        deal(address(_stakingToken), bob, stakingAmount);
        vm.startPrank(bob);
        _stakingToken.approve(address(ohmHoneyAutoStaking), stakingAmount);
        ohmHoneyAutoStaking.stake(stakingAmount);
        vm.stopPrank();

        // Notify reward with a residual
        uint256 rewardAmount = rewardDuration - 1; // This will create a residual
        deal(address(rewardsToken), origamiMultisig, rewardAmount);
        vm.startPrank(origamiMultisig);
        rewardsToken.approve(address(ohmHoneyAutoStaking), rewardAmount);
        ohmHoneyAutoStaking.notifyRewardAmount(address(rewardsToken), rewardAmount);
        vm.stopPrank();

        // Check that the rewardPerToken is zero due to precision loss
        assertEq(ohmHoneyAutoStaking.rewardPerToken(address(rewardsToken)), 0);

        // Skip time to simulate the reward period
        skip(rewardDuration);

        // Check that no rewards are claimable due to precision loss
        uint256 balanceBefore = rewardsToken.balanceOf(bob);
        vm.startPrank(bob);
        ohmHoneyAutoStaking.getReward();
        uint256 balanceAfter = rewardsToken.balanceOf(bob);
        vm.stopPrank();
        assertEq(balanceAfter - balanceBefore, 0);

        // Notify reward again to check if residual is handled
        uint256 additionalRewardAmount = rewardDuration + 1; // Add more to cover residual
        deal(address(rewardsToken), origamiMultisig, additionalRewardAmount);
        vm.startPrank(origamiMultisig);
        rewardsToken.approve(address(ohmHoneyAutoStaking), additionalRewardAmount);
        ohmHoneyAutoStaking.notifyRewardAmount(
            address(rewardsToken), additionalRewardAmount
        );
        vm.stopPrank();

        // Skip time again
        skip(rewardDuration);

        // Check that rewards are now claimable
        balanceBefore = rewardsToken.balanceOf(bob);
        vm.startPrank(bob);
        ohmHoneyAutoStaking.getReward();
        balanceAfter = rewardsToken.balanceOf(bob);
        vm.stopPrank();
        assertGt(balanceAfter, balanceBefore, "Rewards should be claimable");
    }

    function test_earned_multiple() public {
        IERC20 stakingToken = OHM_HONEY;
        vm.startPrank(origamiMultisig);
        addReward(address(stakingToken), address(HONEY), 3600, 10);
        addReward(address(stakingToken), address(WBERA), 3600, 0);
        addReward(address(stakingToken), address(USDC), 3600, 30);

        deal(address(HONEY), origamiMultisig, 100e18);
        HONEY.approve(address(ohmHoneyAutoStaking), 100e18);
        deal(address(WBERA), origamiMultisig, 100e18);
        WBERA.approve(address(ohmHoneyAutoStaking), 100e18);
        deal(address(USDC), origamiMultisig, 100e18);
        USDC.approve(address(ohmHoneyAutoStaking), 100e18);
        ohmHoneyAutoStaking.notifyRewardAmount(address(HONEY), 100e18);
        ohmHoneyAutoStaking.notifyRewardAmount(address(WBERA), 100e18);
        ohmHoneyAutoStaking.notifyRewardAmount(address(USDC), 100e18);
        vm.stopPrank();

        stakeOnBehalfOf(ohmHoneyAutoStaking, address(stakingToken), alice, 1e18);

        // Check total supply
        assertEq(ohmHoneyAutoStaking.totalSupply(), 1e18+1);

        // Simulate time passage
        skip(60);

        // Verify reward per token for rewardToken
        // NB: -48 rounding for rewardResidual in `_notifyRewardAmount()`
        uint256 expectedRewards = uint256(100e18) * 60 / 3600;
        assertEq(ohmHoneyAutoStaking.rewardPerToken(address(HONEY)), expectedRewards*999/1000 - 1);
        assertEq(ohmHoneyAutoStaking.rewardPerToken(address(WBERA)), expectedRewards - 48);
        assertEq(ohmHoneyAutoStaking.rewardPerToken(address(USDC)), expectedRewards*997/1000 - 28);

        // Verify earnings for Alice
        assertEq(ohmHoneyAutoStaking.earned(alice, address(HONEY)), expectedRewards*999/1000 - 1);
        assertEq(ohmHoneyAutoStaking.earned(alice, address(WBERA)), expectedRewards - 48);
        assertEq(ohmHoneyAutoStaking.earned(alice, address(USDC)), expectedRewards*997/1000 - 28);

        vm.prank(alice);
        ohmHoneyAutoStaking.getReward();

        assertEq(HONEY.balanceOf(alice), expectedRewards*999/1000 - 1);
        assertEq(WBERA.balanceOf(alice), expectedRewards - 48);
        assertEq(USDC.balanceOf(alice), expectedRewards*997/1000 - 28);
    }

}

contract OrigamiAutoStakingToErc4626Test_Callbacks is OrigamiAutoStakingToErc4626TestBase {
    function test_onStake_paused() public {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPaused(true, false, false);

        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, 100e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 100e18);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        wberaHoneyAutoStaking.stake(100e18);
    }

    function test_onStake_intoInfraredVault() public {
        uint256 stakeAmount = 100e18;
        deal(alice, stakeAmount);
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, stakeAmount);

        // User approves the infraredVault to spend their tokens
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), stakeAmount);
        uint256 irVaultTotalSupply = IR_WBERA_HONEY.totalSupply();

        // Check stake amount is staked in infrared vault
        vm.expectEmit(address(IR_WBERA_HONEY));
        emit IMultiRewards.Staked(address(wberaHoneyAutoStaking), stakeAmount);
        wberaHoneyAutoStaking.stake(stakeAmount);

        // Check reward vault's balance in infrared vault
        uint256 vaultBalance = IR_WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking));
        assertEq(vaultBalance, stakeAmount, "Rewards vault balance should be updated");

        // Check total supply in the infraredVault
        uint256 totalSupply = IR_WBERA_HONEY.totalSupply();
        assertEq(totalSupply, irVaultTotalSupply+stakeAmount, "Total supply should be updated");

        // Check staking token staked in infrared vault
        assertEq(IR_WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), stakeAmount);
        assertEq(WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(WBERA_HONEY.balanceOf(alice), 0);
    }

    function test_onStake_claimAndDepositIntoOriBgt() public {
        // ibgt rewards is 0 at start
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0, "ibgt balance is 0 at start");
        assertEq(IR_WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0, "ibgt claimable is 0 at start");

        // Stake for user
        uint256 oribgtTotalSupply = ORI_BGT.totalSupply();
        assertEq(oribgtTotalSupply, 1_411_172.742655615111698872e18);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        assertEq(ORI_BGT.totalSupply(), oribgtTotalSupply, "oriBGT total supply remains the same on stake");

        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), 0, "Total unclaimed rewards is 0");
        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        assertEq(earned, 0, "No ibgt rewards");

        // Pass time to earn some ibgt rewards
        skip(7 days);
        earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        assertEq(earned, 0.002040521969010900e18, "Earned ibgt increased");
        uint256 shares = getOriSharesAfterDeposit(earned);

        // Stake again. This time, there is a claimable ibgt amount
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        assertEq(
            ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)),
            shares,
            "Shares of vault after stake is same as calculated"
        );
        assertEq(
            wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)),
            0,
            "Total Unclaimed Rewards isnt updated until notification"
        );

        wberaHoneyAutoStaking.harvestVault();
        assertEq(
            wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)),
            shares*99/100,
            "Total Unclaimed Rewards is updated"
        );
    }

    function test_onStake_postProcessingDisabled() public {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPostProcessingDisabled(true);

        // ibgt rewards is 0 at start
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0, "ibgt balance is 0 at start");
        assertEq(IR_WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0, "ibgt claimable is 0 at start");

        // Stake for user
        uint256 oribgtTotalSupply = ORI_BGT.totalSupply();
        assertEq(oribgtTotalSupply, 1_411_172.742655615111698872e18);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        assertEq(ORI_BGT.totalSupply(), oribgtTotalSupply, "oriBGT total supply remains the same on stake");

        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), 0, "Total unclaimed rewards is 0");
        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        assertEq(earned, 0, "No ibgt rewards");

        // Pass time to earn some ibgt rewards
        skip(7 days);
        earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        assertEq(earned, 0.002040521969010900e18, "Earned ibgt increased");

        // Stake again.
        // No claimable ibgt amount as `postProcessingDisabled=true`
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), 0);

        wberaHoneyAutoStaking.harvestVault();
        assertEq(wberaHoneyAutoStaking.totalUnclaimedRewards(address(ORI_BGT)), 0);
    }

    function test_onWithdraw_paused() public {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPaused(false, true, false);
        
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, 100e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 100e18);
        wberaHoneyAutoStaking.stake(100e18);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        wberaHoneyAutoStaking.withdraw(50e18);
    }

    function test_onWithdraw_claimAndDepositIntoOriBgt() public {
        // Stake for user
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        // Skip time & harvest
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        skip(3 days);

        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        earned = earned + IBGT.balanceOf(address(wberaHoneyAutoStaking));
        uint256 shares = getOriSharesAfterDeposit(earned);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);

        // User withdraws staked amount
        vm.startPrank(alice);
        wberaHoneyAutoStaking.withdraw(100e18);
        assertEq(WBERA_HONEY.balanceOf(alice), 100e18);
        assertEq(
            ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)),
            shares + 0.001933376538900865e18, // no fees taken yet as that's done on notification
            "Shares of vault after withdraw is as calculated"
        );
    }

    function test_onWithdraw_postProcessingEnabled() public {
        // Stake for user
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        // Skip time & harvest
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        skip(3 days);

        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        earned = earned + IBGT.balanceOf(address(wberaHoneyAutoStaking));
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);

        // Pause oriBGT
        {
            address owner = OrigamiDelegated4626Vault(address(ORI_BGT)).owner();
            vm.startPrank(owner);
            IOrigamiManagerPausable manager = IOrigamiManagerPausable(
                OrigamiDelegated4626Vault(address(ORI_BGT)).manager()
            );
            manager.setPauser(owner, true);
            manager.setPaused(IOrigamiManagerPausable.Paused(true, true));
        }

        // Reverts because oriBGT is paused
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        wberaHoneyAutoStaking.withdraw(100e18);

        // Set setPostProcessingDisabled == true
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPostProcessingDisabled(true);

        // User withdraws staked amount
        vm.startPrank(alice);
        wberaHoneyAutoStaking.withdraw(100e18);
        assertEq(WBERA_HONEY.balanceOf(alice), 100e18);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);
    }

    function test_onWithdraw_revertInitialBalance() public {
        // Stake for owner amd alice
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), origamiMultisig, 100e18);
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        skip(3 days);

        // Owner can't fully withdraw all because of the initial balance
        uint256 balance = wberaHoneyAutoStaking.balanceOf(origamiMultisig);
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        wberaHoneyAutoStaking.withdraw(balance);

        // Can withdraw all but the initial balance
        wberaHoneyAutoStaking.withdraw(balance - 1);
        assertEq(WBERA_HONEY.balanceOf(origamiMultisig), balance - 1);

        // Alice can fully exit
        vm.startPrank(alice);
        wberaHoneyAutoStaking.exit();
        assertEq(WBERA_HONEY.balanceOf(alice), 100e18);
    }

    function test_onReward_success() public {
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, 100e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 100e18);
        wberaHoneyAutoStaking.stake(100e18);

        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.135668134542432732e18);
        uint256 earned = wberaHoneyAutoStaking.earned(alice, address(ORI_BGT));
        assertEq(earned, 0.001933376538900500e18);

        wberaHoneyAutoStaking.getReward();
        assertEq(ORI_BGT.balanceOf(address(alice)), 0.001933376538900500e18);
    }

    function test_onReward_paused() public {
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPaused(false, false, true);
        
        vm.startPrank(alice);
        deal(address(WBERA_HONEY), alice, 100e18);
        WBERA_HONEY.approve(address(wberaHoneyAutoStaking), 100e18);
        wberaHoneyAutoStaking.stake(100e18);
        skip(3 days);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.IsPaused.selector));
        wberaHoneyAutoStaking.getReward();
    }

    function test_onExit_claimAndDepositIntoOriBgt() public {
        // Stake for user
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        // Skip time & harvest
        skip(3 days);
        wberaHoneyAutoStaking.harvestVault();
        skip(3 days);

        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        earned = earned + IBGT.balanceOf(address(wberaHoneyAutoStaking));
        uint256 shares = getOriSharesAfterDeposit(earned);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0.001933376538900865e18);
        uint256 aliceEarnedOriBGT = wberaHoneyAutoStaking.earned(alice, address(ORI_BGT));
        assertEq(aliceEarnedOriBGT, 0.001933376538900500e18);

        // User withdraws staked amount
        vm.startPrank(alice);
        wberaHoneyAutoStaking.exit();
        assertEq(WBERA_HONEY.balanceOf(alice), 100e18);
        assertEq(ORI_BGT.balanceOf(alice), aliceEarnedOriBGT);
        assertEq(
            ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)),
            shares + 0.001933376538900865e18 - aliceEarnedOriBGT, // no fees taken yet as that's done on notification
            "Shares of vault after withdraw is as calculated"
        );
    }

    function test_harvestVault_intoOriBgt_success() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        skip(3 days);
        uint256 earned = IR_WBERA_HONEY.earned(address(wberaHoneyAutoStaking), address(IBGT));
        uint256 shares = getOriSharesAfterDeposit(earned);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);

        // harvest
        wberaHoneyAutoStaking.harvestVault();
        assertEq(
            ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)),
            shares*99/100, // 1% fee
            "Shares of vault after harvest is as calculated"
        );
    }

    function test_harvestVault_intoOriBgt_postProcessingDisabled() public {
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);

        skip(3 days);
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);

        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.setPostProcessingDisabled(true);

        // harvest
        wberaHoneyAutoStaking.harvestVault();
        assertEq(ORI_BGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
    }

    function test_notifyOriBgtRewardsHarvestIntoOriBgt() public {
        // Stake for user
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        uint256 oribgtTotalSupply = ORI_BGT.totalSupply();
        assertEq(oribgtTotalSupply, 1_411_172.742655615111698872e18);

        // Pass time to earn some ibgt rewards
        skip(3 days);
        uint256 vaultBalance = ORI_BGT.balanceOf(address(wberaHoneyAutoStaking));
        assertEq(vaultBalance, 0);
        uint256 ibgtEarned = wberaHoneyAutoStaking.unharvestedRewards(address(IBGT));
        assertEq(ibgtEarned, 0.002040521969010900e18);
        uint256 shares = getOriSharesAfterDeposit(ibgtEarned);
        assertEq(shares, 0.001952905594849359e18);

        // claim ibgt rewards and stake into oribgt. distribute oribgt shares as rewards
        vm.startPrank(origamiMultisig);
        wberaHoneyAutoStaking.harvestVault();
        uint256 newVaultBalance = ORI_BGT.balanceOf(address(wberaHoneyAutoStaking));
        uint256 newOribgtTotalSupply = ORI_BGT.totalSupply();

        assertEq(newVaultBalance, 0.001933376538900865e18, "OriBGT balance of vault should increase");
        assertEq(newOribgtTotalSupply, 1_411_172.744608520706548231e18, "OriBGT total supply should increase");
        assertEq(
            shares * 99/100, // 1% fee
            newVaultBalance,
            "Vault OriBGT balance"
        );
        assertEq(IBGT.balanceOf(address(wberaHoneyAutoStaking)), 0);
        assertEq(wberaHoneyAutoStaking.unharvestedRewards(address(IBGT)), 0);
    }

    function test_onWithdraw_fromInfraredVault() public {
        // Stake for user
        stakeOnBehalfOf(wberaHoneyAutoStaking, address(WBERA_HONEY), alice, 100e18);
        uint256 irVaultTotalSupply = IR_WBERA_HONEY.totalSupply();

        // User withdraws partial amount 
        vm.startPrank(alice);
        vm.expectEmit(address(IR_WBERA_HONEY));
        emit IMultiRewards.Withdrawn(address(wberaHoneyAutoStaking), 50e18);
        wberaHoneyAutoStaking.withdraw(50e18);
        uint256 userBalance = WBERA_HONEY.balanceOf(alice);
        uint256 irVaultNewTotalSupply = IR_WBERA_HONEY.totalSupply();

        // Check balances
        assertEq(50e18, userBalance);
        assertEq(irVaultNewTotalSupply, irVaultTotalSupply-50e18);
        assertEq(WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0);

        // User withdraws remaining staked
        wberaHoneyAutoStaking.withdraw(50e18);
        userBalance = WBERA_HONEY.balanceOf(alice);
        irVaultNewTotalSupply = IR_WBERA_HONEY.totalSupply();
        assertEq(100e18, userBalance);
        assertEq(irVaultNewTotalSupply, irVaultTotalSupply-100e18);
        assertEq(WBERA_HONEY.balanceOf(address(wberaHoneyAutoStaking)), 0);
    }

}
