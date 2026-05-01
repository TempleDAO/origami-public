pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginOhmStaking
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginOhmStaking.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginOhmStaking } from "contracts/common/bundler/plugins/OrigamiBundlerPluginOhmStaking.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiBundlerPluginOhmStakingTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    address internal constant OHM_STAKING = 0xB63cac384247597756545b500253ff8E607a8020;
    address internal constant OHM_TOKEN = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address internal constant GOHM_TOKEN = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;

    uint256 internal constant EXPECTED_OHM_PER_GOHM = 269.238508004e18;

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginOhmStaking internal plugin;

    function setUp() public {
        fork("mainnet", 23_617_039);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginOhmStaking(origamiMultisig, OHM_STAKING);

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        vm.stopPrank();
    }
}

contract OrigamiBundlerPluginOhmStakingTestAdmin is OrigamiBundlerPluginOhmStakingTestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertFalse(plugin.isApprovedBundler(alice));
        assertEq(plugin.OLYMPUS_STAKING(), OHM_STAKING);
        assertEq(plugin.OHM(), OHM_TOKEN);
        assertEq(plugin.GOHM(), GOHM_TOKEN);
        assertEq(IERC20(OHM_TOKEN).allowance(address(plugin), OHM_STAKING), type(uint256).max);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), OHM_STAKING), type(uint256).max);
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginOhmStaking).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginOhmStakingTestAccess is OrigamiBundlerPluginOhmStakingTestBase {
    function test_access_stakeToGOhm() public {
        checkInvalidBundler(alice);
        plugin.stakeToGOhm(123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.stakeToGOhm(123, alice);
    }

    function test_access_stakeBalanceToGOhm() public {
        checkInvalidBundler(alice);
        plugin.stakeBalanceToGOhm(alice);

        checkInvalidBundler(origamiMultisig);
        plugin.stakeBalanceToGOhm(alice);
    }

    function test_access_unstakeToOhm() public {
        checkInvalidBundler(alice);
        plugin.unstakeToOhm(123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.unstakeToOhm(123, alice);
    }

    function test_access_unstakeBalanceToOhm() public {
        checkInvalidBundler(alice);
        plugin.unstakeBalanceToOhm(alice);

        checkInvalidBundler(origamiMultisig);
        plugin.unstakeBalanceToOhm(alice);
    }
}

contract OrigamiBundlerPluginOhmStakingTestBundlerActions is OrigamiBundlerPluginOhmStakingTestBase {
    function test_stakeToGOhm_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.stakeToGOhm(123, address(0));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.stakeToGOhm(0, alice);
    }

    function test_stakeToGOhm_success() public {
        deal(OHM_TOKEN, address(plugin), 100e9);

        vm.startPrank(address(bundler));
        uint256 quote1 = plugin.stakeToGOhmQuote(75e9);
        assertEq(quote1, 75e9 * 1e27 / EXPECTED_OHM_PER_GOHM);
        plugin.stakeToGOhm(75e9, alice);

        vm.startPrank(address(bundler));
        uint256 quote2 = plugin.stakeToGOhmQuote(25e9);
        assertEq(quote2, 25e9 * 1e27 / EXPECTED_OHM_PER_GOHM);
        plugin.stakeToGOhm(25e9, address(plugin));

        assertEq(IERC20(OHM_TOKEN).balanceOf(address(alice)), 0);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(plugin)), 0);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(bundler)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(alice)), quote1);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(plugin)), quote2);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(bundler)), 0);
    }

    function test_stakeBalanceToGOhm_failParams() public {
        deal(OHM_TOKEN, address(plugin), 100e9);
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.stakeBalanceToGOhm(address(0));
    }

    function test_stakeBalanceToGOhm_success() public {
        deal(OHM_TOKEN, address(plugin), 100e9);

        vm.startPrank(address(bundler));
        uint256 quote1 = plugin.stakeToGOhmQuote(100e9);
        assertEq(quote1, 100e9 * 1e27 / EXPECTED_OHM_PER_GOHM);
        plugin.stakeBalanceToGOhm(alice);

        // no balance remaining
        vm.startPrank(address(bundler));
        uint256 quote2 = plugin.stakeToGOhmQuote(0);
        assertEq(quote2, 0 * 1e27 / EXPECTED_OHM_PER_GOHM);
        plugin.stakeBalanceToGOhm(address(plugin));

        assertEq(IERC20(OHM_TOKEN).balanceOf(address(alice)), 0);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(plugin)), 0);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(bundler)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(alice)), quote1);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(plugin)), quote2);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(bundler)), 0);
    }

    function test_unstakeToOhm_failParams() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.unstakeToOhm(123, address(0));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.unstakeToOhm(0, alice);
    }

    function test_unstakeToOhm_success() public {
        deal(GOHM_TOKEN, address(plugin), 100e18);

        vm.startPrank(address(bundler));
        uint256 quote1 = plugin.unstakeToOhmQuote(75e18);
        assertEq(quote1, 75e18 * EXPECTED_OHM_PER_GOHM / 1e27);
        plugin.unstakeToOhm(75e18, alice);

        vm.startPrank(address(bundler));
        uint256 quote2 = plugin.unstakeToOhmQuote(25e18);
        assertEq(quote2, 25e18 * EXPECTED_OHM_PER_GOHM / 1e27);
        plugin.unstakeToOhm(25e18, address(plugin));

        assertEq(IERC20(OHM_TOKEN).balanceOf(address(alice)), quote1);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(plugin)), quote2);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(bundler)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(alice)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(bundler)), 0);
    }

    function test_unstakeBalanceToOhm_failParams() public {
        deal(GOHM_TOKEN, address(plugin), 100e18);
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.unstakeBalanceToOhm(address(0));
    }

    function test_unstakeBalanceToOhm_success() public {
        deal(GOHM_TOKEN, address(plugin), 100e18);

        vm.startPrank(address(bundler));
        uint256 quote1 = plugin.unstakeToOhmQuote(100e18);
        assertEq(quote1, 100e18 * EXPECTED_OHM_PER_GOHM / 1e27);
        plugin.unstakeBalanceToOhm(alice);

        // no balance remaining
        vm.startPrank(address(bundler));
        uint256 quote2 = plugin.unstakeToOhmQuote(0);
        assertEq(quote2, 0 * 1e27 / EXPECTED_OHM_PER_GOHM);
        plugin.unstakeBalanceToOhm(address(plugin));

        assertEq(IERC20(OHM_TOKEN).balanceOf(address(alice)), quote1);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(plugin)), quote2);
        assertEq(IERC20(OHM_TOKEN).balanceOf(address(bundler)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(alice)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(address(bundler)), 0);
    }
}
