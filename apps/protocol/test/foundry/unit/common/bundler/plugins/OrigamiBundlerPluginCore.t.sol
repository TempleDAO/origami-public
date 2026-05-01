pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";

contract MockPluginCore is OrigamiBundlerPluginCore {
    error BundlerNotMatching(address expected, address actual);
    error InitiatorNotMatching(address expected, address actual);
    error ReenterHasnNotMatching(bytes32 expected, bytes32 actual);

    address private immutable approvedBundler1;
    address private immutable approvedBundler2;

    uint256 public callDepth;

    constructor(address _approvedBundler1, address _approvedBundler2) {
        approvedBundler1 = _approvedBundler1;
        approvedBundler2 = _approvedBundler2;
    }

    function isApprovedBundler(address account) public view override returns (bool) {
        return account == approvedBundler1 || account == approvedBundler2;
    }

    function checkAddresses(address expectedBundler, address expectedInitiator) external /*view*/  withApprovedBundler {
        address actual = bundler();
        if (actual != expectedBundler) revert BundlerNotMatching(expectedBundler, actual);

        actual = actual == address(0) ? address(0) : OrigamiBundler(actual).initiatorT();
        if (actual != expectedInitiator) revert InitiatorNotMatching(expectedInitiator, actual);
    }

    function reenterBundle(bytes calldata callbackData) external withApprovedBundler {
        callDepth += 1;
        _reenterBundle(callbackData);
    }

    function otherBundlerMulticall(OrigamiBundler otherBundler, Call[] calldata calls) external withApprovedBundler {
        otherBundler.multicall(calls);
    }
}

contract OrigamiBundlerPluginCoreTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    DummyMintableTokenPermissionless internal ASSET1;
    DummyMintableTokenPermissionless internal ASSET2;
    OrigamiBundler internal bundler1;
    OrigamiBundler internal bundler2;
    OrigamiBundler internal bundler3;

    MockPluginCore internal plugin;
    MockPluginCore internal pluginOther;

    function setUp() public {
        ASSET1 = new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18);
        vm.label(address(ASSET1), "ASSET1");
        ASSET2 = new DummyMintableTokenPermissionless("ASSET2", "ASSET2", 18);
        vm.label(address(ASSET2), "ASSET2");

        bundler1 = new OrigamiBundler();
        vm.label(address(bundler1), "bundler1");
        bundler2 = new OrigamiBundler();
        vm.label(address(bundler2), "bundler2");
        bundler3 = new OrigamiBundler();
        vm.label(address(bundler3), "bundler3");

        plugin = new MockPluginCore(address(bundler1), address(bundler2));
        vm.label(address(plugin), "plugin");

        pluginOther = new MockPluginCore(address(bundler1), address(bundler2));
        vm.label(address(pluginOther), "pluginOther");
    }
}

contract OrigamiBundlerPluginCoreTestAdmin is OrigamiBundlerPluginCoreTestBase {
    function test_initialization() public view {
        assertEq(plugin.bundler(), address(0)); // transient
        assertTrue(plugin.isApprovedBundler(address(bundler1)));
        assertTrue(plugin.isApprovedBundler(address(bundler2)));
        assertFalse(plugin.isApprovedBundler(alice));
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerPluginCoreTestAccess is OrigamiBundlerPluginCoreTestBase {
    function test_access_erc20Transfer() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        plugin.erc20Transfer(address(ASSET1), alice, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        plugin.erc20Transfer(address(ASSET1), alice, 0);
    }

    function test_access_erc20TransferBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        plugin.erc20TransferBalance(address(ASSET1), alice, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        plugin.erc20TransferBalance(address(ASSET1), alice, 0);
    }
}

contract OrigamiBundlerPluginCoreTestErc20Transfer is OrigamiBundlerPluginCoreTestBase {
    function test_erc20Transfer_failBadParams() public {
        vm.startPrank(address(bundler1));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.erc20Transfer(address(ASSET1), address(0), 1e18);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(plugin)));
        plugin.erc20Transfer(address(ASSET1), address(plugin), 1e18);
    }

    function test_erc20Transfer_failZeroAmount() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.erc20Transfer(address(ASSET1), alice, 0);
    }

    function test_erc20Transfer_success() public {
        vm.startPrank(address(bundler1));
        deal(address(ASSET1), address(plugin), 123e18);
        plugin.erc20Transfer(address(ASSET1), alice, 33e18);
        assertEq(ASSET1.balanceOf(alice), 33e18);
        assertEq(ASSET1.balanceOf(address(plugin)), 123e18 - 33e18);
    }

    function test_erc20Transfer_failBadToken() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert("Address: call to non-contract");
        plugin.erc20Transfer(bob, alice, 1e18);
    }

    function test_erc20TransferBalance_failBadParams() public {
        vm.startPrank(address(bundler1));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        plugin.erc20TransferBalance(address(ASSET1), address(0), 1e18);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(plugin)));
        plugin.erc20TransferBalance(address(ASSET1), address(plugin), 1e18);
    }

    function test_erc20TransferBalance_successZeroBalance() public {
        vm.startPrank(address(bundler1));
        plugin.erc20TransferBalance(address(ASSET1), alice, 0);
        assertEq(ASSET1.balanceOf(alice), 0);
        assertEq(ASSET1.balanceOf(address(plugin)), 0);
    }

    function test_erc20TransferBalance_failSlippage() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 1, 0));
        plugin.erc20TransferBalance(address(ASSET1), alice, 1);

        deal(address(ASSET1), address(plugin), 123e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.Slippage.selector, 123e18 + 1, 123e18));
        plugin.erc20TransferBalance(address(ASSET1), alice, 123e18 + 1);
    }

    function test_erc20TransferBalance_success() public {
        vm.startPrank(address(bundler1));
        deal(address(ASSET1), address(plugin), 123e18);
        plugin.erc20TransferBalance(address(ASSET1), alice, 33e18);
        assertEq(ASSET1.balanceOf(alice), 123e18);
        assertEq(ASSET1.balanceOf(address(plugin)), 0);
    }
}

contract OrigamiBundlerPluginCoreTestReentry is OrigamiBundlerPluginCoreTestBase {
    function test_reenterBundle_failBadCalldata() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert();
        plugin.reenterBundle("");
    }

    function test_reenterBundle_failWhenCalledDirect() public {
        vm.startPrank(address(bundler1));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.IncorrectReenterHash.selector));
        plugin.reenterBundle(abi.encode(new Call[](0)));
    }

    function test_reenterBundle_failEmptyBundle() public {
        vm.startPrank(address(bundler1));

        Call[] memory innerBundle = new Call[](0);
        bytes memory encodedInnerBundle = abi.encode(innerBundle);
        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedInnerBundle)),
                keccak256(encodedInnerBundle)
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.EmptyBundle.selector));
        bundler1.multicall(outerBundle);
    }

    function test_reenterBundle_success1Deep() public {
        /*
        bundler1.muticall(
            // bundler=bundler1, initiator=origamiMultisig
            plugin.erc20Transfer(),
            reenter(
                // bundler=bundler1, initiator=origamiMultisig
                plugin.erc20Transfer(),
            ),
            plugin.erc20Transfer(),
        )
        */

        deal(address(ASSET1), address(plugin), 100e18);

        Call[] memory innerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedInnerBundle)),
                keccak256(encodedInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );

        vm.startPrank(origamiMultisig);
        bundler1.multicall(outerBundle);

        assertEq(plugin.callDepth(), 1);
        assertEq(plugin.bundler(), address(0));
        assertEq(bundler1.initiatorT(), address(0));
        assertEq(bundler2.initiatorT(), address(0));
        assertEq(ASSET1.balanceOf(address(plugin)), 97e18);
        assertEq(ASSET1.balanceOf(alice), 3e18);
    }

    function test_reenterBundle_success2Deep() public {
        /*
        bundler1.muticall(
            // bundler=bundler1, initiator=origamiMultisig
            plugin.erc20Transfer(),
            reenter(
                // bundler=bundler1, initiator=origamiMultisig
                plugin.erc20Transfer(),
                reenter(
                    // bundler=bundler1, initiator=origamiMultisig
                    plugin.erc20Transfer(),
                ),
                plugin.erc20Transfer(),
            ),
            plugin.erc20Transfer(),
        )
        */

        deal(address(ASSET1), address(plugin), 100e18);

        Call[] memory mostInnerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );
        bytes memory encodedMostInnerBundle = abi.encode(mostInnerBundle);

        Call[] memory innerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedMostInnerBundle)),
                keccak256(encodedMostInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedInnerBundle)),
                keccak256(encodedInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );

        vm.startPrank(origamiMultisig);
        bundler1.multicall(outerBundle);

        assertEq(plugin.callDepth(), 2);
        assertEq(plugin.bundler(), address(0));
        assertEq(bundler1.initiatorT(), address(0));
        assertEq(bundler2.initiatorT(), address(0));
        assertEq(ASSET1.balanceOf(address(plugin)), 95e18);
        assertEq(ASSET1.balanceOf(alice), 5e18);
    }

    function test_multicallAcrossBundlers() public {
        /*
        Within the context of reenter(), it must be the same bundler
        but it doesnt prevent a non-plugin from being called as part of the multicall steps.

        bundler1.muticall(
            // bundler=bundler1, initiator=origamiMultisig
            plugin.erc20Transfer(),
            bundler2.multicall(
                // bundler=bundler2, initiator=bundler1
                reenter(
                    // bundler=bundler2, initiator=bundler1
                    plugin.erc20Transfer(),
                ),
                plugin.erc20Transfer(),
            )
        )
        */

        deal(address(ASSET1), address(plugin), 100e18);

        Call[] memory mostInnerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 2, initiator is bundler1
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler2), address(bundler1)))
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler2), address(bundler1))))
        );
        bytes memory encodedMostInnerBundle = abi.encode(mostInnerBundle);

        Call[] memory innerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 2, initiator is bundler1
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler2), address(bundler1)))
            ),
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedMostInnerBundle)),
                keccak256(encodedMostInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler2), address(bundler1))))
        );

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 1, caller is the multisig
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(
                IOrigamiBundlerPlugin(address(bundler2)), // call on bundler2
                abi.encodeCall(IOrigamiBundler.multicall, (innerBundle))
            ),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );

        vm.startPrank(origamiMultisig);
        bundler1.multicall(outerBundle);

        assertEq(plugin.callDepth(), 1);
        assertEq(plugin.bundler(), address(0));
        assertEq(bundler1.initiatorT(), address(0));
        assertEq(bundler2.initiatorT(), address(0));
        assertEq(ASSET1.balanceOf(address(plugin)), 97e18);
        assertEq(ASSET1.balanceOf(alice), 3e18);
    }

    function test_multicallAcrossBundlers_failNotApproved() public {
        /*
        Can't call bundler3 even if it's nested, since it's not whitelisted.
        */

        deal(address(ASSET1), address(plugin), 100e18);

        Call[] memory mostInnerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 2, initiator is bundler1
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler3), address(bundler1)))
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler3), address(bundler1))))
        );
        bytes memory encodedMostInnerBundle = abi.encode(mostInnerBundle);

        Call[] memory innerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 2, initiator is bundler1
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler3), address(bundler1)))
            ),
            createCall(
                plugin,
                abi.encodeCall(MockPluginCore.reenterBundle, (encodedMostInnerBundle)),
                keccak256(encodedMostInnerBundle)
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler3), address(bundler1))))
        );

        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                // It's via bundler 1, caller is the multisig
                abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))
            ),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(
                IOrigamiBundlerPlugin(address(bundler3)), // call on bundler3
                abi.encodeCall(IOrigamiBundler.multicall, (innerBundle))
            ),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, address(bundler3)));
        bundler1.multicall(outerBundle);
    }

    function test_multicallAcrossBundlers_failMixedBundlers() public {
        /*
        Mixed bundlers not allowed - eg bundler1 calls a function on the plugin
        which calls a plugin function via another bundler (requires complex call chain)
        */

        deal(address(ASSET1), address(plugin), 100e18);

        Call[] memory otherBundle = mkArray(
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18)))
        );

        Call[] memory outerBundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig))),
            createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18))),
            createCall(plugin, abi.encodeCall(MockPluginCore.otherBundlerMulticall, (bundler2, otherBundle))),
            createCall(plugin, abi.encodeCall(MockPluginCore.checkAddresses, (address(bundler1), origamiMultisig)))
        );

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, address(bundler2)));
        bundler1.multicall(outerBundle);
    }

    function test_acrossMultiplePlugins_success() public {
        deal(address(ASSET1), address(plugin), 100e18);
        Call[] memory outerBundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), address(pluginOther), 1e18))
            ),
            createCall(pluginOther, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 1e18)))
        );

        vm.startPrank(origamiMultisig);
        bundler1.multicall(outerBundle);
        assertEq(ASSET1.balanceOf(address(plugin)), 99e18);
        assertEq(ASSET1.balanceOf(address(pluginOther)), 0);
        assertEq(ASSET1.balanceOf(alice), 1e18);
    }
}
