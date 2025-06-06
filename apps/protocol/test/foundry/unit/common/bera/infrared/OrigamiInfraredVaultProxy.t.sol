// NOTE(chachlex): needs migration to bera mainnet or bepolia
// pragma solidity ^0.8.19;
// // SPDX-License-Identifier: AGPL-3.0-or-later

// import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
// import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

// import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
// import { OrigamiInfraredVaultProxy } from "contracts/common/bera/infrared/OrigamiInfraredVaultProxy.sol";
// import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";
// import { stdError } from "forge-std/StdError.sol";

// contract OrigamiInfraredVaultProxyTestBase is OrigamiTest {
//     IERC20 internal constant iBgtToken = IERC20(0x7D6e08fe0d56A7e8f9762E9e65daaC491A0B475b);
//     address internal constant beraRewardsVault = 0x7D949A79259d55Da7da18EF947468B6E0b34f5cf;
//     IInfraredVault internal infraredVault = IInfraredVault(0x380605d60386682Ef8a0e79F4eC0b45A08bce171);
//     address internal constant infrared = 0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219;

//     IERC20 internal constant lpToken = IERC20(0xF7F214A9543c1153eF5DF2edCd839074615F248c);
//     uint256 internal constant IBGT_MONTHLY_REWARDS = 30_000e18; // 1k / day
//     uint256 internal constant HONEY_WEEKLY_REWARDS = 3_500e18; // 500k / day
//     IERC20 internal constant honeyToken = IERC20(0xd137593CDB341CcC78426c54Fb98435C60Da193c);

//     OrigamiInfraredVaultProxy internal staker;

//     function setUp() public virtual {
//         fork("berachain_cartio_testnet", 4048000);
//         staker = new OrigamiInfraredVaultProxy(origamiMultisig, address(infraredVault));

//         _setIBgtReward();
//     }

//     function _setIBgtReward() internal {
//         deal(address(iBgtToken), infrared, IBGT_MONTHLY_REWARDS);
//         vm.startPrank(infrared);
//         iBgtToken.approve(address(infraredVault), IBGT_MONTHLY_REWARDS);
//         infraredVault.notifyRewardAmount(address(iBgtToken), IBGT_MONTHLY_REWARDS);
//         vm.stopPrank();
//     }
// }

// contract OrigamiInfraredVaultProxyTestAdmin is OrigamiInfraredVaultProxyTestBase {
//     event Approval(address indexed owner, address indexed spender, uint256 value);

//     function test_initialization() public view {
//         assertEq(staker.owner(), origamiMultisig);
//         assertEq(staker.infrared(), infrared);
//         assertEq(address(staker.infraredVault()), address(infraredVault));
//         assertEq(address(staker.stakingToken()), address(lpToken));
//         assertEq(address(staker.rewardsVault()), beraRewardsVault);

//         address[] memory rewardTokens = staker.getAllRewardTokens();
//         assertEq(rewardTokens.length, 1);
//         assertEq(rewardTokens[0], address(iBgtToken));

//         uint256[] memory rewardsForDuration = staker.getRewardsForDuration();
//         assertEq(rewardsForDuration.length, 1);
//         assertEq(rewardsForDuration[0], 30_000e18 - 192000);

//         uint256[] memory rewardsPerToken = staker.getRewardsPerToken();
//         assertEq(rewardsPerToken.length, 1);
//         assertEq(rewardsPerToken[0], 0);

//         IMultiRewards.Reward[] memory data = staker.rewardsData();
//         assertEq(data.length, 1);
//         assertEq(data[0].rewardsDistributor, infrared);
//         assertEq(data[0].rewardsDuration, 30 days);
//         assertEq(data[0].periodFinish, 1739130006);
//         assertEq(data[0].rewardRate, 11574074074074074);
//         assertEq(data[0].lastUpdateTime, 1736538006);
//         assertEq(data[0].rewardPerTokenStored, 0);
//         assertEq(data[0].rewardResidual, 192000);

//         assertEq(staker.totalSupply(), 1); // Infrared has a stake
//         assertEq(staker.stakedBalance(), 0);
//     }

//     function test_recoverToken_success() public {
//         check_recoverToken(address(staker));
//     }

//     function test_setTokenAllowance() public {
//         vm.startPrank(origamiMultisig);
//         DummyMintableToken token = new DummyMintableToken(origamiMultisig, "MOCK", "MOCK", 18);
//         DummyMintableToken spender = new DummyMintableToken(origamiMultisig, "SPENDER", "SPENDER", 18);

//         assertEq(token.allowance(address(staker), address(spender)), 0);

//         vm.expectEmit(address(token));
//         emit Approval(address(staker), address(spender), type(uint256).max);

//         staker.setTokenAllowance(
//             address(token),
//             address(spender),
//             type(uint256).max
//         );
//         assertEq(token.allowance(address(staker), address(spender)), type(uint256).max);

//         staker.setTokenAllowance(
//             address(token),
//             address(spender),
//             type(uint256).max
//         );
//     }
// }

// contract OrigamiInfraredVaultProxyTestAccess is OrigamiInfraredVaultProxyTestBase {   
//     function test_stake_access() public {
//         expectElevatedAccess();
//         staker.stake(0);
//     }
    
//     function test_withdraw_access() public {
//         expectElevatedAccess();
//         staker.withdraw(0, alice);
//     }
    
//     function test_exit_access() public {
//         expectElevatedAccess();
//         staker.exit(alice);
//     }

//     function test_getRewards_access() public {
//         expectElevatedAccess();
//         staker.getRewards(alice);
//     }
    
//     function test_recoverToken_access() public {
//         expectElevatedAccess();
//         staker.recoverToken(alice, alice, 100e18);
//     }
    
//     function test_setTokenAllowance_access() public {
//         expectElevatedAccess();
//         staker.setTokenAllowance(alice, alice, 100e18);
//     }
// }

// contract OrigamiInfraredVaultProxyTestRewardsVault_OnlyIBgt is OrigamiInfraredVaultProxyTestBase {

//     function test_stake_failNoApproval() public {
//         vm.startPrank(origamiMultisig);

//         staker.setTokenAllowance(address(lpToken), address(infraredVault), 99e18);
//         vm.expectRevert("TRANSFER_FROM_FAILED");
//         staker.stake(100e18);
//     }

//     function test_stake_zeroAmount() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert("Cannot stake 0");
//         staker.stake(0);
//     }

//     function test_stake_success() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);
//         assertEq(infraredVault.balanceOf(address(staker)), amount);
//         assertEq(staker.totalSupply(), amount+1);
//         assertEq(staker.stakedBalance(), amount);
//     }

//     function test_withdraw_zeroAmount() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
//         staker.withdraw(0, alice);
//     }

//     function test_withdraw_fail_badRecipient() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         staker.withdraw(123, address(0));
//     }

//     function test_withdraw_fail_tooMuch() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(stdError.arithmeticError);
//         staker.withdraw(123, alice);
//     }

//     function test_withdraw_withRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         staker.withdraw(amount/2, alice);
//         staker.withdraw(amount/4, address(staker));

//         assertEq(infraredVault.balanceOf(address(staker)), 25e18);
//         assertEq(lpToken.balanceOf(address(staker)), 25e18);
//         assertEq(lpToken.balanceOf(address(alice)), 50e18);
//     }

//     function test_exit_fail_badRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);

//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         staker.exit(address(0));
//     }

//     function test_exit_toSelf() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);

//         // If neither addresses are set, the rewards aren't set to the recipient
//         staker.exit(address(staker));

//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 1_000e18 - 6500); // infrared rounding
//     }

//     function test_exit_toOther() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         staker.exit(alice);
//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), amount);
//         assertEq(iBgtToken.balanceOf(alice), 1_000e18 - 6500);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//     }

//     function test_exit_fail_noRewards() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         // Nothing to transfer since no time elapsed
//         staker.exit(address(staker));

//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), 0);
//         assertEq(iBgtToken.balanceOf(alice), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//     }

//     function test_exit_zeroToTransfer() public {
//         vm.startPrank(origamiMultisig);

//         vm.expectRevert("Cannot withdraw 0");
//         staker.exit(alice);
//     }

//     function test_getRewards_noRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         uint256 expectedReward = 1_000e18 - 6500;
//         assertEq(staker.stakedBalance(), amount);
//         IInfraredVault.UserReward[] memory unclaimed = staker.unclaimedRewards();
//         assertEq(unclaimed.length, 1);
//         assertEq(unclaimed[0].token, address(iBgtToken));
//         assertEq(unclaimed[0].amount, expectedReward);

//         staker.getRewards(alice);
//         assertEq(infraredVault.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//         assertEq(iBgtToken.balanceOf(address(alice)), expectedReward);

//         skip(1 days);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         staker.getRewards(address(0));
//     }

//     function test_getRewards_zeroAmount() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         staker.getRewards(alice);
//         assertEq(infraredVault.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//     }
// }

// contract OrigamiInfraredVaultProxyTestRewardsVault_WithHoney is OrigamiInfraredVaultProxyTestBase {
//     function setUp() public override {
//         OrigamiInfraredVaultProxyTestBase.setUp();
//         _addHoneyReward();
//     }

//     function _addHoneyReward() internal {
//         vm.startPrank(infrared);
//         infraredVault.addReward(address(honeyToken), 7 days);

//         deal(address(honeyToken), infrared, HONEY_WEEKLY_REWARDS);
//         honeyToken.approve(address(infraredVault), HONEY_WEEKLY_REWARDS);
//         infraredVault.notifyRewardAmount(address(honeyToken), HONEY_WEEKLY_REWARDS);
//         vm.stopPrank();
//     }

//     function test_views() public view {
//         address[] memory rewardTokens = staker.getAllRewardTokens();
//         assertEq(rewardTokens.length, 2);
//         assertEq(rewardTokens[0], address(iBgtToken));
//         assertEq(rewardTokens[1], address(honeyToken));

//         uint256[] memory rewardsForDuration = staker.getRewardsForDuration();
//         assertEq(rewardsForDuration.length, 2);
//         assertEq(rewardsForDuration[0], 30_000e18 - 192000);
//         assertEq(rewardsForDuration[1], 3_500e18 - 22400);

//         uint256[] memory rewardsPerToken = staker.getRewardsPerToken();
//         assertEq(rewardsPerToken.length, 2);
//         assertEq(rewardsPerToken[0], 0);
//         assertEq(rewardsPerToken[1], 0);

//         IMultiRewards.Reward[] memory data = staker.rewardsData();
//         assertEq(data.length, 2);
//         assertEq(data[0].rewardsDistributor, infrared);
//         assertEq(data[0].rewardsDuration, 30 days);
//         assertEq(data[0].periodFinish, 1739130006);
//         assertEq(data[0].rewardRate, 11574074074074074);
//         assertEq(data[0].lastUpdateTime, 1736538006);
//         assertEq(data[0].rewardPerTokenStored, 0);
//         assertEq(data[0].rewardResidual, 192000);
//         assertEq(data[1].rewardsDistributor, infrared);
//         assertEq(data[1].rewardsDuration, 7 days);
//         assertEq(data[1].periodFinish, 1737142806);
//         assertEq(data[1].rewardRate, 5787037037037037);
//         assertEq(data[1].lastUpdateTime, 1736538006);
//         assertEq(data[1].rewardPerTokenStored, 0);
//         assertEq(data[1].rewardResidual, 22400);

//         assertEq(staker.totalSupply(), 1); // Infrared has a stake
//         assertEq(staker.stakedBalance(), 0);
//     }

//     function test_exit_toSelf() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);

//         // If neither addresses are set, the rewards aren't set to the recipient
//         staker.exit(address(staker));

//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 1_000e18 - 6500); // infrared rounding
//         assertEq(honeyToken.balanceOf(address(staker)), 500e18 - 3300); // infrared rounding
//     }

//     function test_exit_toOther() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         staker.exit(alice);
//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), amount);
//         assertEq(iBgtToken.balanceOf(alice), 1_000e18 - 6500);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//         assertEq(honeyToken.balanceOf(alice), 500e18 - 3300);
//         assertEq(honeyToken.balanceOf(address(staker)), 0);
//     }

//     function test_exit_fail_noRewards() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         // Nothing to transfer since no time elapsed
//         staker.exit(address(staker));

//         assertEq(infraredVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), 0);
//         assertEq(iBgtToken.balanceOf(alice), 0);
//         assertEq(honeyToken.balanceOf(alice), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//         assertEq(honeyToken.balanceOf(address(staker)), 0);
//     }

//     function test_getRewards() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         uint256 expectedReward1 = 1_000e18 - 6500;
//         uint256 expectedReward2 = 500e18 - 3300;
//         assertEq(staker.stakedBalance(), amount);
//         IInfraredVault.UserReward[] memory unclaimed = staker.unclaimedRewards();
//         assertEq(unclaimed.length, 2);
//         assertEq(unclaimed[0].token, address(iBgtToken));
//         assertEq(unclaimed[0].amount, expectedReward1);
//         assertEq(unclaimed[1].token, address(honeyToken));
//         assertEq(unclaimed[1].amount, expectedReward2);

//         staker.getRewards(alice);
//         assertEq(infraredVault.balanceOf(address(staker)), amount);
//         assertEq(iBgtToken.balanceOf(address(staker)), 0);
//         assertEq(iBgtToken.balanceOf(address(alice)), expectedReward1);
//         assertEq(honeyToken.balanceOf(address(alice)), expectedReward2);
//     }
// }