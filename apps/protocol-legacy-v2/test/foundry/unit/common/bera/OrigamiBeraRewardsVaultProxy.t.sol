// NOTE(chachlex): needs migration to bera mainnet or bepolia
// pragma solidity ^0.8.19;
// // SPDX-License-Identifier: AGPL-3.0-or-later

// import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
// import { OrigamiBeraRewardsVaultProxy } from "contracts/common/bera/OrigamiBeraRewardsVaultProxy.sol";
// import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";
// import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
// import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";

// contract OrigamiBeraRewardsVaultProxyTestBase is OrigamiTest {

//     IBeraBgt internal constant bgtToken = IBeraBgt(0x289274787bAF083C15A45a174b7a8e44F0720660);
//     IBeraRewardsVault internal constant beraRewardsVault = IBeraRewardsVault(0x7D949A79259d55Da7da18EF947468B6E0b34f5cf);
//     IERC20 internal constant lpToken = IERC20(0xF7F214A9543c1153eF5DF2edCd839074615F248c);

//     OrigamiBeraRewardsVaultProxy internal staker;

//     function setUp() public {
//         fork("berachain_cartio_testnet", 1392348);
//         staker = new OrigamiBeraRewardsVaultProxy(origamiMultisig, address(beraRewardsVault));
//     }
// }

// contract OrigamiBeraRewardsVaultProxyTestAdmin is OrigamiBeraRewardsVaultProxyTestBase {
//     event Approval(address indexed owner, address indexed spender, uint256 value);

//     function test_initialization() public view {
//         assertEq(staker.owner(), origamiMultisig);
//         assertEq(address(staker.rewardsVault()), address(beraRewardsVault));
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

// contract OrigamiBeraRewardsVaultProxyTestAccess is OrigamiBeraRewardsVaultProxyTestBase {
//     function test_recoverToken_access() public {
//         expectElevatedAccess();
//         staker.recoverToken(alice, alice, 100e18);
//     }
    
//     function test_setTokenAllowance_access() public {
//         expectElevatedAccess();
//         staker.setTokenAllowance(alice, alice, 100e18);
//     }
    
//     function test_setOperator_access() public {
//         expectElevatedAccess();
//         staker.setOperator(alice);
//     }
    
//     function test_stake_access() public {
//         expectElevatedAccess();
//         staker.stake(0);
//     }
    
//     function test_withdraw_access() public {
//         expectElevatedAccess();
//         staker.withdraw(0, alice);
//     }
    
//     function test_delegateStake_access() public {
//         expectElevatedAccess();
//         staker.delegateStake(alice, 0);
//     }
    
//     function test_delegateWithdraw_access() public {
//         expectElevatedAccess();
//         staker.delegateWithdraw(alice, 0, alice);
//     }
    
//     function test_exit_access() public {
//         expectElevatedAccess();
//         staker.exit(alice);
//     }
    
//     function test_getReward_access() public {
//         expectElevatedAccess();
//         staker.getReward(alice);
//     }
// }

// contract OrigamiBeraRewardsVaultProxyTestRewardsVault is OrigamiBeraRewardsVaultProxyTestBase {
//     error WithdrawAmountIsZero();
//     error ERC20InvalidReceiver(address);
//     error StakeAmountIsZero();
//     error InsufficientSelfStake();

//     function test_setOperator() public {
//         vm.startPrank(origamiMultisig);
//         staker.setOperator(alice);
//         assertEq(beraRewardsVault.operator(address(staker)), alice);
//     }

//     function test_stake_failNoApproval() public {
//         vm.startPrank(origamiMultisig);

//         staker.setTokenAllowance(address(lpToken), address(beraRewardsVault), 99e18);
//         vm.expectRevert("BAL#414");
//         staker.stake(100e18);
//     }

//     function test_stake_zeroAmount() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(StakeAmountIsZero.selector));
        
//         staker.stake(0);
//     }

//     function test_stake_success() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);
//         assertEq(beraRewardsVault.balanceOf(address(staker)), amount);
//     }

//     function test_withdraw_zeroAmount() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(WithdrawAmountIsZero.selector));
//         staker.withdraw(0, alice);
//     }

//     function test_withdraw_fail_badRecipient() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         staker.withdraw(123, address(0));
//     }

//     function test_withdraw_fail_tooMuch() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(InsufficientSelfStake.selector));
//         staker.withdraw(123, alice);
//     }

//     function test_withdraw_withRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         staker.withdraw(amount/2, alice);
//         staker.withdraw(amount/4, address(staker));

//         assertEq(beraRewardsVault.balanceOf(address(staker)), 25e18);
//         assertEq(lpToken.balanceOf(address(staker)), 25e18);
//         assertEq(lpToken.balanceOf(address(alice)), 50e18);
//     }

//     function test_delegateStake() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.delegateStake(bob, amount);
//         assertEq(beraRewardsVault.balanceOf(address(staker)), 0);
//         assertEq(beraRewardsVault.balanceOf(address(bob)), amount);
//         assertEq(beraRewardsVault.getDelegateStake(bob, address(staker)), amount);
//         assertEq(beraRewardsVault.getTotalDelegateStaked(bob), amount);
//     }

//     function test_delegateWithdraw_fail_badRecipient() public {
//         vm.startPrank(origamiMultisig);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         staker.delegateWithdraw(bob, 123, address(0));
//     }

//     function test_delegateWithdraw_withRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.delegateStake(bob, amount);

//         // If neither addresses are set, the rewards aren't set to the recipient
//         staker.delegateWithdraw(bob, amount/2, alice);
//         staker.delegateWithdraw(bob, amount/4, address(staker));

//         assertEq(beraRewardsVault.balanceOf(address(bob)), amount/4);
//         assertEq(lpToken.balanceOf(address(staker)), amount/4);
//         assertEq(lpToken.balanceOf(address(alice)), amount/2);
//         assertEq(beraRewardsVault.getDelegateStake(bob, address(staker)), amount/4);
//         assertEq(beraRewardsVault.getTotalDelegateStaked(bob), amount/4);
//     }

//     function test_exit_fail_badRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);

//         vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
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

//         assertEq(beraRewardsVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(bgtToken.balanceOf(address(staker)), 0.0108418811354099e18);
//     }

//     function test_exit_toOther() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         staker.exit(alice);
//         assertEq(beraRewardsVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), amount);
//         assertEq(bgtToken.balanceOf(alice), 0.0108418811354099e18);
//         assertEq(bgtToken.balanceOf(address(staker)), 0);
//     }

//     function test_exit_fail_noRewards() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         // Nothing to transfer since no time elapsed
//         staker.exit(address(staker));

//         assertEq(beraRewardsVault.balanceOf(address(staker)), 0);
//         assertEq(lpToken.balanceOf(alice), 0);
//         assertEq(bgtToken.balanceOf(alice), 0);
//         assertEq(lpToken.balanceOf(address(staker)), amount);
//         assertEq(bgtToken.balanceOf(address(staker)), 0);
//     }

//     function test_exit_zeroToTransfer() public {
//         vm.startPrank(origamiMultisig);

//         vm.expectRevert(WithdrawAmountIsZero.selector);
//         staker.exit(alice);
//     }

//     function test_getReward_noRecipient() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         uint256 expectedReward = 0.010841881135409900e18;
//         assertEq(staker.stakedBalance(), amount);
//         assertEq(staker.unclaimedRewardsBalance(), expectedReward);
//         staker.getReward(alice);
//         assertEq(beraRewardsVault.balanceOf(address(staker)), amount);
//         assertEq(bgtToken.balanceOf(address(staker)), 0);
//         assertEq(bgtToken.balanceOf(address(alice)), expectedReward);

//         skip(1 days);
//         vm.expectRevert(abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0)));
//         staker.getReward(address(0));
//     }

//     function test_getReward_zeroAmount() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         staker.getReward(alice);
//         assertEq(beraRewardsVault.balanceOf(address(staker)), amount);
//         assertEq(bgtToken.balanceOf(address(staker)), 0);
//     }

//     function test_getReward_failBgtTransfer() public {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);

//         // Can't transfer BGT
//         // vm.expectRevert(0xf2d81d95); // expect this is a custom error that we can't transfer BGT...
//         staker.getReward(alice);
//         assertEq(bgtToken.balanceOf(address(alice)), 0.0108418811354099e18);
//     }
// }