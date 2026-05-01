pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";

import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundlerPluginCore } from "contracts/common/bundler/plugins/OrigamiBundlerPluginCore.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { Vm } from "forge-std/Test.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract BundlerWithWhitelist is OrigamiBundler {
    mapping(address plugin => bool allowed) public whitelisted;

    function whitelist(address plugin, bool approved) public {
        whitelisted[plugin] = approved;
    }

    function isApprovedPlugin(address plugin) public view override returns (bool) {
        return whitelisted[plugin];
    }

    function setInitiator(address newInitiator) external {
        initiatorT = newInitiator;
    }

    function setReenterHash(bytes32 newReenterHash) external {
        reenterHashT = newReenterHash;
    }
}

contract Empty { }

contract MockPlugin is OrigamiBundlerPluginCore {
    event Initiator(address);
    event ReenterHash(bytes32, uint256);

    address public approvedBundler;

    constructor(address bundler_) {
        approvedBundler = bundler_;
    }

    function isApprovedBundler(address account) public view override returns (bool) {
        return account == approvedBundler;
    }

    function emitReenterHash() public payable {
        emit ReenterHash(IOrigamiBundler(approvedBundler).reenterHashT(), address(this).balance);
    }

    function doRevert(string memory reason) external pure {
        revert(reason);
    }

    function emitInitiator() external {
        emit Initiator(IOrigamiBundler(approvedBundler).initiatorT());
    }

    function callbackBundler(Call[] calldata calls) external withApprovedBundler {
        emitReenterHash();
        IOrigamiBundler(bundler()).reenter(calls);
        emitReenterHash();
    }

    function callbackBundlerTwice(Call[] calldata calls1, Call[] calldata calls2) external withApprovedBundler {
        IOrigamiBundler(bundler()).reenter(calls1);
        IOrigamiBundler(bundler()).reenter(calls2);
    }

    function callbackBundlerWithMulticall() external withApprovedBundler {
        IOrigamiBundler(bundler()).multicall(new Call[](0));
    }

    receive() external payable virtual { }

    function nativeTransferBalance(address receiver, uint256 minAmount) external withApprovedBundler {
        if (receiver == address(0) || receiver == address(this)) revert CommonEventsAndErrors.InvalidAddress(receiver);
        uint256 amount = address(this).balance;
        if (amount < minAmount) revert CommonEventsAndErrors.Slippage(minAmount, amount);
        if (amount > 0) {
            Address.sendValue(payable(receiver), amount);
        }
    }
}

contract OrigamiBundlerTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    DummyMintableTokenPermissionless internal ASSET1;
    DummyMintableTokenPermissionless internal ASSET2;
    OrigamiBundler internal bundler1;
    BundlerWithWhitelist internal bundlerWithWhitelist;

    MockPlugin internal plugin;
    MockPlugin internal pluginOther;

    function setUp() public virtual {
        ASSET1 = new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18);
        vm.label(address(ASSET1), "ASSET1");
        ASSET2 = new DummyMintableTokenPermissionless("ASSET2", "ASSET2", 18);
        vm.label(address(ASSET2), "ASSET2");

        bundler1 = new OrigamiBundler();
        vm.label(address(bundler1), "bundler1");
        bundlerWithWhitelist = new BundlerWithWhitelist();
        vm.label(address(bundlerWithWhitelist), "bundlerWithWhitelist");

        plugin = new MockPlugin(address(bundlerWithWhitelist));
        vm.label(address(plugin), "plugin");

        pluginOther = new MockPlugin(address(bundlerWithWhitelist));
        vm.label(address(pluginOther), "pluginOther");
    }

    // Matches OrigamiBundler::reenter()
    function _reenterHash(address _plugin, Call[] memory _bundle) internal pure returns (bytes32) {
        return EfficientHashLib.hash(bytes32(uint256(uint160(_plugin))), EfficientHashLib.hash(abi.encode(_bundle)));
    }
}

contract OrigamiBundlerTestViews is OrigamiBundlerTestBase {
    function test_isApprovedPluginBase() public view {
        assertTrue(bundler1.isApprovedPlugin(alice));
        assertTrue(bundler1.isApprovedPlugin(address(ASSET1)));
    }

    function test_isApprovedPluginWhitelisted() public {
        assertFalse(bundlerWithWhitelist.isApprovedPlugin(address(plugin)));
        assertFalse(bundlerWithWhitelist.isApprovedPlugin(alice));
        assertFalse(bundlerWithWhitelist.isApprovedPlugin(address(ASSET1)));

        bundlerWithWhitelist.whitelist(address(plugin), true);
        assertTrue(bundlerWithWhitelist.isApprovedPlugin(address(plugin)));
        assertFalse(bundlerWithWhitelist.isApprovedPlugin(alice));
        assertFalse(bundlerWithWhitelist.isApprovedPlugin(address(ASSET1)));
    }

    function test_supportsInterface() public view {
        assertTrue(bundler1.supportsInterface(type(IOrigamiBundler).interfaceId));
        assertTrue(bundler1.supportsInterface(type(IERC165).interfaceId));
        assertFalse(bundler1.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OrigamiBundlerTestMulticall is OrigamiBundlerTestBase {
    function setUp() public override {
        super.setUp();
        bundlerWithWhitelist.whitelist(address(plugin), true);
    }

    function test_multicall_failEmpty() public {
        vm.expectRevert(IOrigamiBundler.EmptyBundle.selector);
        bundlerWithWhitelist.multicall(new Call[](0));
    }

    function test_reenter_failEmpty() public {
        Call[] memory innerCalls = new Call[](0);

        Call[] memory outerCalls = mkArray(
            createCall(
                plugin, abi.encodeCall(MockPlugin.callbackBundler, (innerCalls)), keccak256(abi.encode(innerCalls))
            )
        );

        vm.expectRevert(IOrigamiBundler.EmptyBundle.selector);
        bundlerWithWhitelist.multicall(outerCalls);
    }

    function test_multicall_zeroToAddress() public {
        Call[] memory calls = mkArray(
            createCall(
                MockPlugin(payable(0)),
                abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 33e18))
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.InvalidPlugin.selector, address(0)));
        bundler1.multicall(calls);
    }

    function test_multicall_failInvalidPlugin() public {
        Call[] memory calls = mkArray(
            createCall(
                pluginOther, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (address(ASSET1), alice, 33e18))
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.InvalidPlugin.selector, address(pluginOther)));
        bundlerWithWhitelist.multicall(calls);
    }

    function test_fuzz_multicall_failAlreadyInitiated(address initiator) public {
        vm.assume(initiator != address(0));
        Call[] memory calls = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.callbackBundlerWithMulticall, ())));

        vm.startPrank(initiator);
        vm.expectRevert(IOrigamiBundler.AlreadyInitiated.selector);
        bundlerWithWhitelist.multicall(calls);
    }

    function test_multicall_failAlreadyInitiated() public {
        address initiator = alice;
        Call[] memory calls = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.callbackBundlerWithMulticall, ())));

        vm.startPrank(initiator);
        vm.expectRevert(IOrigamiBundler.AlreadyInitiated.selector);
        bundlerWithWhitelist.multicall(calls);
    }

    function test_multicall_recoverValueLeftOver() public {
        address initiator = alice;
        Call[] memory calls = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ())));

        uint256 value = 1e18;
        vm.deal(initiator, value);
        vm.startPrank(initiator);

        vm.expectEmit(address(plugin));
        emit MockPlugin.Initiator(initiator);
        bundlerWithWhitelist.multicall{ value: value }(calls);

        // Value is left in the bundler...
        assertEq(initiator.balance, 0);
        assertEq(address(plugin).balance, 0);
        assertEq(address(bundlerWithWhitelist).balance, value);

        // Can be recovered via another call however.
        calls = mkArray(
            Call({ to: address(plugin), data: "", value: value, skipRevert: false, callbackHash: bytes32(0) }),
            createCall(plugin, abi.encodeCall(MockPlugin.nativeTransferBalance, (alice, 0)))
        );
        bundlerWithWhitelist.multicall(calls);
        assertEq(initiator.balance, value);
        assertEq(address(plugin).balance, 0);
        assertEq(address(bundlerWithWhitelist).balance, 0);
    }

    function test_fuzz_multicall_passthroughValue(address initiator, uint128 value) public {
        vm.assume(initiator != address(0));
        Call[] memory calls = mkArray(
            Call({
                to: address(plugin),
                data: abi.encodeCall(MockPlugin.emitReenterHash, ()),
                value: value,
                skipRevert: false,
                callbackHash: bytes32(0)
            })
        );

        vm.deal(initiator, value);
        vm.startPrank(initiator);

        vm.expectCall(address(plugin), value, bytes.concat(MockPlugin.emitReenterHash.selector));
        vm.expectEmit(address(plugin));
        emit MockPlugin.ReenterHash(bytes32(0), value);
        bundlerWithWhitelist.multicall{ value: value }(calls);
    }

    function test_fuzz_multicall_failPluginNotPayable(address initiator, uint128 value) public {
        vm.assume(initiator != address(0));
        Call[] memory calls = mkArray(
            Call({
                to: address(plugin),
                data: abi.encodeCall(MockPlugin.emitInitiator, ()),
                value: value,
                skipRevert: false,
                callbackHash: bytes32(0)
            })
        );

        vm.deal(initiator, value);
        vm.startPrank(initiator);

        if (value > 0) vm.expectRevert();
        bundlerWithWhitelist.multicall{ value: value }(calls);
    }

    function test_fuzz_multicall_nestedCallbackAndReenterHashValue(address initiator) public {
        vm.assume(initiator != address(0));
        MockPlugin plugin1 = new MockPlugin(address(bundler1));
        MockPlugin plugin2 = new MockPlugin(address(bundler1));
        MockPlugin plugin3 = new MockPlugin(address(bundler1));

        Call[] memory callbackBundle2 = mkArray(createCall(plugin2, abi.encodeCall(MockPlugin.emitReenterHash, ())));
        Call[] memory callbackBundle = mkArray(
            createCall(
                plugin2,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle2)),
                keccak256(abi.encode(callbackBundle2))
            ),
            createCall(
                plugin3,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle2)),
                keccak256(abi.encode(callbackBundle2))
            )
        );

        Call[] memory bundle = mkArray(
            createCall(
                plugin1,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)),
                keccak256(abi.encode(callbackBundle))
            )
        );

        vm.prank(initiator);

        vm.recordLogs();
        bundler1.multicall(bundle);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 8);

        for (uint256 i = 0; i < entries.length; i++) {
            assertEq(entries[i].topics[0], keccak256("ReenterHash(bytes32,uint256)"));
        }

        bytes32 reenterHash1 = _reenterHash(address(plugin1), callbackBundle);
        bytes32 reenterHash2 = _reenterHash(address(plugin2), callbackBundle2);
        bytes32 reenterHash3 = _reenterHash(address(plugin3), callbackBundle2);

        assertEq(entries[0].data, abi.encode(reenterHash1, 0));
        assertEq(entries[1].data, abi.encode(reenterHash2, 0));
        assertEq(entries[2].data, abi.encode(bytes32(0), 0));
        assertEq(entries[3].data, abi.encode(bytes32(0), 0));
        assertEq(entries[4].data, abi.encode(reenterHash3, 0));
        assertEq(entries[5].data, abi.encode(bytes32(0), 0));
        assertEq(entries[6].data, abi.encode(bytes32(0), 0));
        assertEq(entries[7].data, abi.encode(bytes32(0), 0));
    }

    function test_fuzz_multicall_shouldSetTheRightInitiator(address initiator) public {
        vm.assume(initiator != address(0));
        MockPlugin plugin1 = new MockPlugin(address(bundler1));

        Call[] memory bundle = mkArray(createCall(plugin1, abi.encodeCall(MockPlugin.emitInitiator, ())));

        vm.expectEmit(address(plugin1));
        emit MockPlugin.Initiator(initiator);

        vm.prank(initiator);
        bundler1.multicall(bundle);

        // Test that the initiator is reset.
        assertEq(bundler1.initiatorT(), address(0));
    }

    function test_fuzz_multicall_shouldPassRevertData(string memory revertReason) public {
        MockPlugin plugin1 = new MockPlugin(address(bundler1));
        Call[] memory bundle = mkArray(createCall(plugin1, abi.encodeCall(MockPlugin.doRevert, (revertReason))));
        vm.expectRevert(bytes(revertReason));
        bundler1.multicall(bundle);
    }

    function test_fuzz_reenter_failIncorrectHash(address initiator, bytes32 badHash, address caller) public {
        vm.assume(initiator != address(0));
        vm.assume(caller != initiator);

        bundlerWithWhitelist.setInitiator(initiator);
        bundlerWithWhitelist.setReenterHash(badHash);

        vm.expectRevert(IOrigamiBundler.IncorrectReenterHash.selector);
        vm.prank(caller);
        bundlerWithWhitelist.reenter(new Call[](0));
    }

    function test_fuzz_reenter_successAsMockPlugin(address initiator, address mockPlugin) public {
        vm.assume(initiator != address(0));
        vm.assume(initiator != mockPlugin);

        Call[] memory bundle = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ())));

        bundlerWithWhitelist.setInitiator(initiator);
        bundlerWithWhitelist.setReenterHash(_reenterHash(mockPlugin, bundle));

        vm.startPrank(mockPlugin);
        vm.expectEmit(address(plugin));
        emit MockPlugin.Initiator(initiator);
        bundlerWithWhitelist.reenter(bundle);
    }

    function test_multicall_failNotSkipRevert() public {
        address empty = address(new Empty());

        // Check that this produces a failing call.
        vm.prank(alice);
        (bool success,) = empty.call(hex"");
        assertFalse(success);

        Call[] memory bundle =
            mkArray(Call({ to: empty, data: hex"", value: 0, skipRevert: false, callbackHash: bytes32(0) }));

        vm.prank(alice);
        vm.expectRevert();
        bundler1.multicall(bundle);
    }

    function test_fuzz_multicall_innerBundleFailing(bool skipOuter, bool skipInner) public {
        Call[] memory callbackBundle = mkArray(
            Call({
                to: address(plugin),
                data: abi.encodeCall(MockPlugin.doRevert, ("planned revert")),
                value: 0,
                skipRevert: skipInner,
                callbackHash: bytes32(0)
            })
        );

        Call[] memory bundle = mkArray(
            Call({
                to: address(plugin),
                data: abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)),
                value: 0,
                skipRevert: skipOuter,
                callbackHash: keccak256(abi.encode(callbackBundle))
            })
        );

        if (!skipOuter && !skipInner) {
            vm.expectRevert("planned revert");
        } else if (skipOuter && !skipInner) {
            // @note This reverts with MissingExpectedReenter because the reenterHashT isn't reset to bytes32(0)
            // from the inner call which  failed
            vm.expectRevert(IOrigamiBundler.MissingExpectedReenter.selector);
        } else if (skipOuter && skipInner) {
            // No revert expected
        } else if (!skipOuter && skipInner) {
            // No revert expected because the inner is skipped
        }

        bundlerWithWhitelist.multicall(bundle);
    }

    function test_multicall_successSkipRevert() public {
        address empty = address(new Empty());

        vm.prank(alice);
        bundler1.multicall(
            mkArray(Call({ to: empty, data: hex"", value: 0, skipRevert: true, callbackHash: bytes32(0) }))
        );
    }

    function test_fuzz_multicall_failBadReenterHash(bytes32 badHash) public {
        Call[] memory callbackBundle = new Call[](0);
        bytes32 goodHash = _reenterHash(address(plugin), callbackBundle);
        vm.assume(badHash != goodHash);

        Call[] memory bundle =
            mkArray(createCall(plugin, abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)), badHash));

        vm.expectRevert(IOrigamiBundler.IncorrectReenterHash.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_successGoodReenterHash(uint256 size) public {
        size = bound(size, 1, 100);
        Call[] memory callbackBundle = new Call[](size);
        for (uint256 i; i < size; ++i) {
            callbackBundle[i] = createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()));
        }

        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)),
                keccak256(abi.encode(callbackBundle))
            )
        );

        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_failNestedBadReenterHash(bytes32 badHash) public {
        Call[] memory calls = new Call[](0);

        bytes32 goodHash = _reenterHash(address(plugin), calls);
        vm.assume(badHash != goodHash);

        Call[] memory callbackBundle =
            mkArray(createCall(plugin, abi.encodeCall(MockPlugin.callbackBundler, (calls)), badHash));

        Call[] memory bundle = mkArray(
            createCall(
                plugin,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)),
                keccak256(abi.encode(callbackBundle))
            )
        );

        vm.expectRevert(IOrigamiBundler.IncorrectReenterHash.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_failSequentialReenter(uint256 size1, uint256 size2) public {
        size1 = bound(size1, 1, 10);
        size2 = bound(size2, 1, 10);
        Call[] memory calls1 = new Call[](size1);
        for (uint256 i; i < size1; ++i) {
            calls1[i] = createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()));
        }

        Call[] memory calls2 = new Call[](size2);
        for (uint256 i; i < size2; ++i) {
            calls2[i] = createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()));
        }

        Call[] memory bundle = mkArray(
            createCall(
                plugin, abi.encodeCall(MockPlugin.callbackBundlerTwice, (calls1, calls2)), keccak256(abi.encode(calls1))
            )
        );

        vm.expectRevert(IOrigamiBundler.IncorrectReenterHash.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_failMissedReenter(bytes32 _hash) public {
        vm.assume(_hash != bytes32(0));

        Call[] memory bundle = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()), _hash));

        vm.expectRevert(IOrigamiBundler.MissingExpectedReenter.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_multicall_failMissedReenter() public {
        bytes32 _hash = "bad hash";

        Call[] memory bundle = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()), _hash));

        vm.expectRevert(IOrigamiBundler.MissingExpectedReenter.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_failMissedReenterFollowedByActionWithReenter(bytes32 _hash) public {
        vm.assume(_hash != bytes32(0));

        Call[] memory callbackBundle = mkArray(createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ())));

        Call[] memory bundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()), _hash),
            createCall(
                plugin,
                abi.encodeCall(MockPlugin.callbackBundler, (callbackBundle)),
                keccak256(abi.encode(callbackBundle))
            )
        );

        vm.expectRevert(IOrigamiBundler.MissingExpectedReenter.selector);
        bundlerWithWhitelist.multicall(bundle);
    }

    function test_fuzz_multicall_failMissedReenterFollowedByActionWithoutReenter(bytes32 _hash) public {
        vm.assume(_hash != bytes32(0));

        Call[] memory bundle = mkArray(
            createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()), _hash),
            createCall(plugin, abi.encodeCall(MockPlugin.emitInitiator, ()))
        );

        vm.expectRevert(IOrigamiBundler.MissingExpectedReenter.selector);
        bundlerWithWhitelist.multicall(bundle);
    }
}
