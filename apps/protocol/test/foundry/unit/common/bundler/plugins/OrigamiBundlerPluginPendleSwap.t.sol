// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { PendleRouterScalingLib } from "pendle-router-scaling/src/PendleRouterScalingLib.sol";
import {
    PendleRouterScalingLibTest,
    ScalingContractWrapper
} from "pendle-router-scaling/test/PendleRouterScalingLib.t.sol";
import { TestBase as PendleScalingTestBase } from "pendle-router-scaling/test/TestBase.sol";

import { OrigamiBundlerPluginPendleSwap } from "contracts/common/bundler/plugins/OrigamiBundlerPluginPendleSwap.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginPendleSwap
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginPendleSwap.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";

contract OrigamiBundlerPluginPendleSwapTestBase is OrigamiTest {
    OrigamiBundler internal bundler;
    OrigamiBundlerPluginPendleSwap internal plugin;
    address public constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    function setUp() public {
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginPendleSwap(origamiMultisig, PENDLE_ROUTER_V4);

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }

    function checkInvalidBundler(address user) internal {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, user));
    }
}

contract OrigamiBundlerPluginPendleSwapTestAdmin is OrigamiBundlerPluginPendleSwapTestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertFalse(plugin.isApprovedBundler(alice));
        assertEq(plugin.ROUTER(), PENDLE_ROUTER_V4);
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginPendleSwap).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginPendleSwapTestAccess is OrigamiBundlerPluginPendleSwapTestBase {
    function test_access_swap() public {
        checkInvalidBundler(alice);
        plugin.swap(alice, "");

        checkInvalidBundler(origamiMultisig);
        plugin.swap(alice, "");
    }

    function test_access_swapBalance() public {
        checkInvalidBundler(alice);
        plugin.swapBalance(alice, "");

        checkInvalidBundler(origamiMultisig);
        plugin.swapBalance(alice, "");
    }
}

contract OrigamiBundlerPluginPendleSwapScaleCalldataTest is PendleRouterScalingLibTest {
    address public origamiMultisig = makeAddr("origamiMultisig");

    function testDataPath() internal view override returns (string memory) {
        return string.concat(vm.projectRoot(), "/lib/pendle-router-scaling/test/calldata.json");
    }

    function setUp() public override {
        scaler = ScalingContractWrapper(address(new OrigamiBundlerPluginPendleSwap(origamiMultisig, PENDLE_ROUTER_V4)));
    }
}

contract OrigamiBundlerPluginPendleSwapForkTest is PendleScalingTestBase {
    OrigamiBundlerPluginPendleSwap public plugin;
    OrigamiBundler internal bundler;

    address receiver;
    address public origamiMultisig = makeAddr("origamiMultisig");
    uint256 snapId;

    // Got more than expected
    uint256 public constant TOLERANCE_MORE = 0.0001e18; // 0.01%

    // Got less than expected
    uint256 public constant TOLERANCE_LESS = 0.0004e18; // 0.04%

    function setUp() public {
        CalldataItem[] memory testItems = loadTestItems();

        // Use the min blockNumber as the fork
        CalldataItem memory item;
        uint256 forkBlockNumber = type(uint256).max;
        for (uint256 i; i < testItems.length; ++i) {
            item = testItems[i];
            if (item.blockNumber < forkBlockNumber) {
                forkBlockNumber = item.blockNumber;
            }

            if (receiver == address(0)) {
                receiver = item.from;
            } else if (receiver != item.from) {
                revert("All test cases need the same 'from'");
            }
        }

        fork("mainnet", forkBlockNumber);

        // Etch the plugin onto the receiver address that was used when generating the test cases
        {
            OrigamiBundlerPluginPendleSwap br = new OrigamiBundlerPluginPendleSwap(origamiMultisig, PENDLE_ROUTER_V4);
            vm.etch(receiver, address(br).code);
            plugin = OrigamiBundlerPluginPendleSwap(receiver);

            // Update the owner to our multisig so we can approve the bundler
            // After the fork it started off as a regular address not a contract
            {
                vm.prank(plugin.owner());
                plugin.proposeNewOwner(origamiMultisig);
                vm.prank(origamiMultisig);
                plugin.acceptOwner();
            }

            bundler = new OrigamiBundler();
            vm.prank(origamiMultisig);
            plugin.setBundlerApproved(address(bundler), true);
        }

        // Snapshot the state so it can easily be restored.
        // NB: vm.rollFork() didn't reset all the state before
        snapId = vm.snapshotState();
    }

    function testDataPath() internal view override returns (string memory) {
        return string.concat(vm.projectRoot(), "/lib/pendle-router-scaling/test/calldata.json");
    }

    // No change to calldata, deal existing amounts
    function test_swap_as_is() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            vm.revertToState(snapId);
            CalldataItem memory item = testItems[i];
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal exact tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = item.amountInBN;
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(plugin), 0);

            vm.prank(address(bundler));
            plugin.swap(item.tokenInAddr, item.data);

            assertEq(IERC20(item.tokenInAddr).balanceOf(address(plugin)), dealtAmount - item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(plugin));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // No change to calldata, deal an extra 5% which is just left over in the contract and not
    // used by the pendle router
    function test_swap_with_extra() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            vm.revertToState(snapId);
            CalldataItem memory item = testItems[i];
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal an extra 5% of tokens and call swap. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = add5Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(plugin), 0);

            vm.prank(address(bundler));
            plugin.swap(item.tokenInAddr, item.data);

            assertEq(IERC20(item.tokenInAddr).balanceOf(address(plugin)), dealtAmount - item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(plugin));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // No change to calldata, deal an extra 5% which is just left over in the contract and not
    // used by the pendle router
    function test_swapBalance_as_is() public {
        CalldataItem[] memory testItems = loadTestItems();

        for (uint256 i; i < testItems.length; ++i) {
            vm.revertToState(snapId);
            CalldataItem memory item = testItems[i];
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal exact tokens and call swapBalance. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = item.amountInBN;
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(plugin), 0);

            vm.startPrank(address(bundler));
            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                plugin.swapBalance(item.tokenInAddr, item.data);
                vm.stopPrank();
                continue;
            }

            plugin.swapBalance(item.tokenInAddr, item.data);
            vm.stopPrank();
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(plugin)), dealtAmount - item.amountInBN);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(plugin));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // With scaled calldata, deal an extra 5% which is all used and we get more output tokens
    function test_swapBalance_with_extra() public {
        CalldataItem[] memory testItems = loadTestItems();

        // We get an extra amount of output tokens when we deal extra
        uint256 _TOLERANCE_MORE = 0.06e18; // 6%

        for (uint256 i; i < testItems.length; ++i) {
            vm.revertToState(snapId);
            CalldataItem memory item = testItems[i];
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal an extra 5% of tokens and call swapBalance. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = add5Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(plugin), 0);

            vm.startPrank(address(bundler));
            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                plugin.swapBalance(item.tokenInAddr, item.data);
                vm.stopPrank();
                continue;
            }

            plugin.swapBalance(item.tokenInAddr, item.data);
            vm.stopPrank();
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(plugin)), 0);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(plugin));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, _TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_LESS, itemKey);
            }
        }
    }

    // With scaled calldata, deal an extra 5% which is all used and we get more output tokens
    function test_swapBalance_with_less() public {
        CalldataItem[] memory testItems = loadTestItems();

        // We get LESS amount of output tokens when we dont deal as much
        uint256 _TOLERANCE_LESS = 0.04e18; // 4%

        for (uint256 i; i < testItems.length; ++i) {
            vm.revertToState(snapId);
            CalldataItem memory item = testItems[i];
            string memory itemKey = string(bytes.concat(bytes(vm.toString(i)), " ", bytes(item.method)));

            // Deal 3% less of the tokens and call swapBalance. Ensure the router starts with zero tokenOut
            uint256 dealtAmount = sub3Pct(item.amountInBN);
            deal(item.tokenInAddr, item.from, dealtAmount);
            deal(item.tokenOutAddr, address(plugin), 0);

            vm.startPrank(address(bundler));
            if (isUnsupported(bytes4(item.data))) {
                vm.expectRevert(
                    abi.encodeWithSelector(PendleRouterScalingLib.UnsupportedSelector.selector, bytes4(item.data))
                );
                plugin.swapBalance(item.tokenInAddr, item.data);
                vm.stopPrank();
                continue;
            } else if (needsScaleNotSet(bytes4(item.data))) {
                vm.expectRevert("TransferHelper: TRANSFER_FROM_FAILED");
                plugin.swapBalance(item.tokenInAddr, item.data);
                vm.stopPrank();
                continue;
            }

            plugin.swapBalance(item.tokenInAddr, item.data);
            vm.stopPrank();
            assertEq(IERC20(item.tokenInAddr).balanceOf(address(plugin)), 0);

            uint256 outBalance = IERC20(item.tokenOutAddr).balanceOf(address(plugin));
            if (outBalance > item.amountOutBN) {
                assertApproxEqRel(outBalance, item.amountOutBN, TOLERANCE_MORE, itemKey);
            } else {
                assertApproxEqRel(outBalance, item.amountOutBN, _TOLERANCE_LESS, itemKey);
            }
        }
    }

    function test_swapBalance_noBalance() public {
        deal(USDC_TOKEN, address(plugin), 0);
        vm.startPrank(address(bundler));

        plugin.swapBalance(USDC_TOKEN, hex"");
        assertEq(IERC20(USDC_TOKEN).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDC_TOKEN).allowance(address(plugin), PENDLE_ROUTER_V4), 0);
    }
}
