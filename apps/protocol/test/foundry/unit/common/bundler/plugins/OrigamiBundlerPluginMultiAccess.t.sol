pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";

contract OrigamiBundlerMultiAccessTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    DummyMintableTokenPermissionless internal ASSET1;
    OrigamiBundler internal bundler1;
    OrigamiBundler internal bundler2;
    OrigamiBundler internal bundler3;

    OrigamiBundlerPluginMultiAccess internal plugin;

    function setUp() public {
        ASSET1 = new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18);
        vm.label(address(ASSET1), "ASSET1");

        bundler1 = new OrigamiBundler();
        vm.label(address(bundler1), "bundler1");
        bundler2 = new OrigamiBundler();
        vm.label(address(bundler2), "bundler2");
        bundler3 = new OrigamiBundler();
        vm.label(address(bundler3), "bundler3");

        plugin = new OrigamiBundlerPluginMultiAccess(origamiMultisig);
        vm.label(address(plugin), "plugin");
    }
}

contract OrigamiBundlerMultiAccessTestAdmin is OrigamiBundlerMultiAccessTestBase {
    function test_initialization() public view {
        assertEq(plugin.bundler(), address(0)); // transient
        assertFalse(plugin.approvedBundlers(address(bundler1)));
        assertFalse(plugin.approvedBundlers(address(bundler2)));
        assertFalse(plugin.approvedBundlers(address(bundler3)));

        assertFalse(plugin.isApprovedBundler(address(bundler1)));
        assertFalse(plugin.isApprovedBundler(address(bundler2)));
        assertFalse(plugin.isApprovedBundler(address(bundler3)));
        assertFalse(plugin.isApprovedBundler(alice));
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }

    function test_setBundlerApproved_failNotBundler_true() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert( /* "call to non-contract address 0x328809Bc894f92807417D2dAD6b7C998c1aFdac6" */ );
        plugin.setBundlerApproved(alice, true);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, address(plugin)));
        plugin.setBundlerApproved(address(plugin), true);
    }

    function test_setBundlerApproved_failNotBundler_false() public {
        vm.startPrank(origamiMultisig);
        emit IOrigamiBundlerPluginMultiAccess.BundlerApprovedSet(alice, true);
        plugin.setBundlerApproved(alice, false);
        assertFalse(plugin.approvedBundlers(alice));

        emit IOrigamiBundlerPluginMultiAccess.BundlerApprovedSet(address(plugin), true);
        plugin.setBundlerApproved(address(plugin), false);
        assertFalse(plugin.approvedBundlers(address(plugin)));
    }

    function test_setBundlerApproved_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(plugin));
        emit IOrigamiBundlerPluginMultiAccess.BundlerApprovedSet(address(bundler1), true);
        plugin.setBundlerApproved(address(bundler1), true);

        assertTrue(plugin.approvedBundlers(address(bundler1)));
        assertTrue(plugin.isApprovedBundler(address(bundler1)));
        assertFalse(plugin.approvedBundlers(address(bundler2)));
        assertFalse(plugin.isApprovedBundler(address(bundler2)));

        vm.expectEmit(address(plugin));
        emit IOrigamiBundlerPluginMultiAccess.BundlerApprovedSet(address(bundler1), false);
        plugin.setBundlerApproved(address(bundler1), false);
        assertFalse(plugin.approvedBundlers(address(bundler1)));
        assertFalse(plugin.isApprovedBundler(address(bundler1)));
    }

    // Core plugin functions still work too
    function test_erc20Transfer_beforeAndAfterApproval() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, address(bundler1)));
        plugin.erc20Transfer(address(ASSET1), alice, type(uint256).max);

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler1), true);

        deal(address(ASSET1), address(plugin), 1e18);
        vm.startPrank(address(bundler1));
        plugin.erc20Transfer(address(ASSET1), alice, 1e18);
        assertEq(ASSET1.balanceOf(alice), 1e18);
        assertEq(ASSET1.balanceOf(address(plugin)), 0);
    }
}

contract OrigamiBundlerMultiAccessTestAccess is OrigamiBundlerMultiAccessTestBase {
    function test_access_setBundlerApproved() public {
        expectElevatedAccess();
        plugin.setBundlerApproved(alice, true);
    }

    function test_access_erc20Transfer() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        plugin.erc20Transfer(address(ASSET1), alice, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        plugin.erc20Transfer(address(ASSET1), alice, 0);
    }
}
