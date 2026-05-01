// NOTE(chachlex): needs migration to bera mainnet or bepolia
// pragma solidity ^0.8.19;
// // SPDX-License-Identifier: AGPL-3.0-or-later

// import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
// import { OrigamiBeraBgtProxy } from "contracts/common/bera/OrigamiBeraBgtProxy.sol";
// import { OrigamiBeraRewardsVaultProxy } from "contracts/common/bera/OrigamiBeraRewardsVaultProxy.sol";
// import { IBeraBgt } from "contracts/interfaces/external/bera/IBeraBgt.sol";
// import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
// import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
// import { stdError } from "forge-std/StdError.sol";
// import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

// contract OrigamiBeraBgtProxyTestBase is OrigamiTest {

//     IBeraBgt internal constant bgtToken = IBeraBgt(0x289274787bAF083C15A45a174b7a8e44F0720660);
//     IBeraRewardsVault internal constant beraRewardsVault = IBeraRewardsVault(0x7D949A79259d55Da7da18EF947468B6E0b34f5cf);
//     IERC20 internal constant lpToken = IERC20(0xF7F214A9543c1153eF5DF2edCd839074615F248c);

//     OrigamiBeraBgtProxy internal impl;
//     OrigamiBeraBgtProxy internal bgtProxy;

//     OrigamiBeraRewardsVaultProxy private staker;
//     bytes internal validatorPubKey;

//     function setUp() public {
//         fork("berachain_cartio_testnet", 1392348);
    
//         impl = new OrigamiBeraBgtProxy(address(bgtToken));
//         bytes memory initData = abi.encodeCall(OrigamiBeraBgtProxy.initialize, origamiMultisig);       
//         bgtProxy = OrigamiBeraBgtProxy(address(
//             new ERC1967Proxy(address(impl), initData)
//         ));

//         staker = new OrigamiBeraRewardsVaultProxy(origamiMultisig, address(beraRewardsVault));
//         validatorPubKey = "0x89c8b925d5d0e4233df6db338efc41a2529b31da77e088b03087ce9cd6f7f61552a806fdeced8d7a51ec5c6b4827e387";
//     }

//     function earnBgt() internal {
//         vm.startPrank(origamiMultisig);

//         uint256 amount = 100e18;
//         deal(address(lpToken), address(staker), amount);
//         staker.stake(amount);

//         skip(1 days);
//         staker.getReward(address(bgtProxy));
//     }
// }

// contract OrigamiBeraBgtProxyTestAdmin is OrigamiBeraBgtProxyTestBase {
//     event Upgraded(address indexed implementation);
//     event Approval(address indexed owner, address indexed spender, uint256 value);

//     function test_construction_fail() public {
//         bytes memory data = abi.encodeCall(OrigamiBeraBgtProxy.initialize, address(0));       
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
//         OrigamiBeraBgtProxy(address(new ERC1967Proxy(address(impl), data)));
//     }

//     function test_initialization() public view {
//         assertEq(bgtProxy.owner(), origamiMultisig);
//         assertEq(impl.owner(), address(0));
//         assertEq(address(bgtProxy.bgt()), address(bgtToken));
//         assertEq(address(impl.bgt()), address(bgtToken));
//     }

//     function test_upgrade_fail() public {
//         vm.startPrank(alice);
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
//         bgtProxy.upgradeTo(address(impl));
//     }

//     function test_upgrade_success() public {
//         vm.startPrank(origamiMultisig);
//         impl = new OrigamiBeraBgtProxy(address(bgtToken));
//         vm.expectEmit(address(bgtProxy));
//         emit Upgraded(address(impl));
//         bgtProxy.upgradeTo(address(impl));
//     }

//     function test_upgradeToAndCall_failAccess() public {
//         // Grant bob access to upgrade (only) 
//         vm.prank(origamiMultisig);
//         setExplicitAccess(bgtProxy, bob, UUPSUpgradeable.upgradeToAndCall.selector, true);

//         vm.startPrank(bob);
//         impl = new OrigamiBeraBgtProxy(address(bgtToken));
//         vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
//         bgtProxy.upgradeToAndCall(address(impl), abi.encodeWithSelector(IOrigamiElevatedAccess.proposeNewOwner.selector, bob));
//     }

//     function test_recoverToken_success() public {
//         check_recoverToken(address(bgtProxy));
//     }

//     function test_setTokenAllowance() public {
//         vm.startPrank(origamiMultisig);
//         DummyMintableToken token = new DummyMintableToken(origamiMultisig, "MOCK", "MOCK", 18);
//         DummyMintableToken spender = new DummyMintableToken(origamiMultisig, "SPENDER", "SPENDER", 18);

//         assertEq(token.allowance(address(bgtProxy), address(spender)), 0);

//         vm.expectEmit(address(token));
//         emit Approval(address(bgtProxy), address(spender), type(uint256).max);

//         bgtProxy.setTokenAllowance(
//             address(token),
//             address(spender),
//             type(uint256).max
//         );
//         assertEq(token.allowance(address(bgtProxy), address(spender)), type(uint256).max);

//         bgtProxy.setTokenAllowance(
//             address(token),
//             address(spender),
//             type(uint256).max
//         );
//     }
// }

// contract OrigamiBeraBgtProxyTestAccess is OrigamiBeraBgtProxyTestBase {
//     function test_recoverToken_access() public {
//         expectElevatedAccess();
//         bgtProxy.recoverToken(alice, alice, 100e18);
//     }
    
//     function test_setTokenAllowance_access() public {
//         expectElevatedAccess();
//         bgtProxy.setTokenAllowance(alice, alice, 100e18);
//     }
    
//     function test_redeem_access() public {
//         expectElevatedAccess();
//         bgtProxy.redeem(alice, 0);
//     }
    
//     function test_delegate_access() public {
//         expectElevatedAccess();
//         bgtProxy.delegate(alice);
//     }
    
//     function test_queueBoost_access() public {
//         expectElevatedAccess();
//         bgtProxy.queueBoost(validatorPubKey, 0);
//     }
    
//     function test_cancelBoost_access() public {
//         expectElevatedAccess();
//         bgtProxy.cancelBoost(validatorPubKey, 0);
//     }
        
//     function test_queueDropBoost_access() public {
//         expectElevatedAccess();
//         bgtProxy.queueDropBoost(validatorPubKey, 0);
//     }
    
//     function test_cancelDropBoost_access() public {
//         expectElevatedAccess();
//         bgtProxy.cancelDropBoost(validatorPubKey, 0);
//     }
// }

// contract OrigamiBeraBgtProxyTestFunctions is OrigamiBeraBgtProxyTestBase {
//     function test_redeem() public {
//         earnBgt();
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         assertEq(bgtProxy.balance(), 0.0108418811354099e18);
        
//         bgtProxy.redeem(alice, bgtToken.balanceOf(address(bgtProxy)));

//         // No BGT left.
//         // BERA (native) was sent to Alice 1:1
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0);
//         assertEq(alice.balance, 0.0108418811354099e18);
//         assertEq(address(bgtProxy).balance, 0);
//     }

//     function test_delegate() public {
//         earnBgt();

//         // No self votes -- needs explicit delegation
//         assertEq(bgtToken.delegates(address(bgtProxy)), address(0));
//         assertEq(bgtToken.getVotes(address(bgtProxy)), 0);

//         bgtProxy.delegate(bob);

//         assertEq(bgtToken.delegates(address(bgtProxy)), bob);
//         assertEq(bgtToken.getVotes(address(bob)), 0.0108418811354099e18);
//     }

//     function test_queueBoost() public {
//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);

//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);
//         (uint32 blockNumberLast, uint128 balance) = bgtToken.boostedQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 1392348);
//         assertEq(balance, 0.01e18);
//         assertEq(bgtToken.queuedBoost(address(bgtProxy)), 0.01e18);

//         assertEq(bgtToken.boosted(address(bgtProxy), validatorPubKey), 0);
//         assertEq(bgtToken.boosts(address(bgtProxy)), 0);
//         assertEq(bgtToken.boosts(bob), 0);
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0008418811354099e18);
//         assertEq(bgtToken.unboostedBalanceOf(bob), 0);
//     }

//     function test_cancelBoost() public {
//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);

//         vm.expectRevert(stdError.arithmeticError); // underflow from not enough balance
//         bgtProxy.cancelBoost(validatorPubKey, 0.01e18);

//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);
//         bgtProxy.cancelBoost(validatorPubKey, 0.003e18);

//         (uint32 blockNumberLast, uint128 balance) = bgtToken.boostedQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 1392348);
//         assertEq(balance, 0.007e18);
//         assertEq(bgtToken.queuedBoost(address(bgtProxy)), 0.007e18);

//         assertEq(bgtToken.boosted(address(bgtProxy), validatorPubKey), 0);
//         assertEq(bgtToken.boosts(address(bgtProxy)), 0);
//         assertEq(bgtToken.boosts(bob), 0);
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0038418811354099e18);
//         assertEq(bgtToken.unboostedBalanceOf(bob), 0);
//     }

//     function test_activateBoost() public {
//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);

//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);

//         // 8192 blocks need to pass:
//         // https://docs.berachain.com/developers/#key-functions-3
//         vm.roll(block.number + bgtToken.activateBoostDelay() + 1);
//         assertEq(bgtProxy.activateBoost(validatorPubKey), true);

//         (uint32 blockNumberLast, uint128 balance) = bgtToken.boostedQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 0);
//         assertEq(balance, 0);
//         assertEq(bgtToken.queuedBoost(address(bgtProxy)), 0);

//         assertEq(bgtToken.boosted(address(bgtProxy), validatorPubKey), 0.01e18);
//         assertEq(bgtToken.boosts(address(bgtProxy)), 0.01e18);
//         assertEq(bgtToken.boosts(bob), 0);
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0008418811354099e18);
//         assertEq(bgtToken.unboostedBalanceOf(bob), 0);
//     }

//     function test_queueDropBoost() public {
//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);

//         // 8192 blocks need to pass:
//         // https://docs.berachain.com/developers/#key-functions-3
//         vm.roll(block.number + bgtToken.activateBoostDelay() + 1);
//         bgtProxy.activateBoost(validatorPubKey);

//         bgtProxy.queueDropBoost(validatorPubKey, 0.003e18);
//         (uint32 blockNumberLast, uint128 balance) = bgtToken.dropBoostQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 1400540);
//         assertEq(balance, 0.003e18);
//     }

//     function test_cancelDropBoost() public {
//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);

//         // 8192 blocks need to pass:
//         // https://docs.berachain.com/developers/#key-functions-3
//         vm.roll(block.number + bgtToken.activateBoostDelay() + 1);
//         bgtProxy.activateBoost(validatorPubKey);

//         bgtProxy.queueDropBoost(validatorPubKey, 0.003e18);
//         (uint32 blockNumberLast, uint128 balance) = bgtToken.dropBoostQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 1400540);
//         assertEq(balance, 0.003e18);

//         bgtProxy.cancelDropBoost(validatorPubKey, 0.003e18);
//         (blockNumberLast, balance) = bgtToken.dropBoostQueue(address(bgtProxy), validatorPubKey);
//         assertEq(blockNumberLast, 1400540);
//         assertEq(balance, 0);
//     }

//     function test_dropBoost_success() public {
//         // interdasting: The BGT never leaves bgtProxy while this flow happens.

//         earnBgt();
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0108418811354099e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);
        
//         bgtProxy.queueBoost(validatorPubKey, 0.01e18);
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0008418811354099e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);

//         // 8192 blocks need to pass:
//         // https://docs.berachain.com/developers/#key-functions-3
//         vm.roll(block.number + bgtToken.activateBoostDelay() + 1);
//         bgtProxy.activateBoost(validatorPubKey);
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.0008418811354099e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);

//         bgtProxy.queueDropBoost(validatorPubKey, 0.003e18);

//         vm.roll(block.number + bgtToken.dropBoostDelay() + 1);
//         assertEq(bgtProxy.dropBoost(validatorPubKey), true);

//         // Unboosted is increased now
//         assertEq(bgtToken.unboostedBalanceOf(address(bgtProxy)), 0.003841881135409900e18);
//         assertEq(bgtToken.balanceOf(address(bgtProxy)), 0.0108418811354099e18);
//     }
// }