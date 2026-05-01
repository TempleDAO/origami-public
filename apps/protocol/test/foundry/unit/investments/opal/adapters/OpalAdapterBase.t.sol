pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { LibString } from "solady/utils/LibString.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import {
    MockMultiTokenOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMultiTokenOpalAdapter.m.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { MockMerklDistributor } from "test/foundry/unit/investments/erc4626/OrigamiErc4626WithRewardsManager.t.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

contract MockMultiTokenOpalAdapterNoInit is MockMultiTokenOpalAdapter {
    constructor(bytes32 _implTypeAndVersion) MockMultiTokenOpalAdapter(_implTypeAndVersion) { }

    function _adapterInit(
        bytes calldata /*data*/
    )
        internal
        override
    {
        // nothing
    }
}

contract OpalAdapterBaseTestBase is OrigamiTest {
    OpalAdapterFactory internal adapterFactory;
    MockMultiTokenOpalAdapter internal adapterImpl;

    MockMultiTokenOpalAdapter internal adapter;

    DummyMintableTokenPermissionless internal ASSET1;
    DummyMintableTokenPermissionless internal ASSET2;
    DummyMintableTokenPermissionless internal DEBT1;
    DummyMintableTokenPermissionless internal DEBT2;
    address internal manager = makeAddr("manager");
    MockMerklDistributor internal merklRewardsDistributor;

    uint256 internal constant MAX_SAFE_LTV = 0.85e18;

    bytes32 internal DEFAULT_GROUP_ID = bytes32("DEFAULT");

    function setUp() public {
        ASSET1 = new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18);
        vm.label(address(ASSET1), "ASSET1");
        ASSET2 = new DummyMintableTokenPermissionless("ASSET2", "ASSET2", 18);
        vm.label(address(ASSET2), "ASSET2");
        DEBT1 = new DummyMintableTokenPermissionless("DEBT1", "DEBT1", 18);
        vm.label(address(DEBT1), "DEBT1");
        DEBT2 = new DummyMintableTokenPermissionless("DEBT2", "DEBT2", 18);
        vm.label(address(DEBT2), "DEBT2");

        merklRewardsDistributor = new MockMerklDistributor();
        deal(address(ASSET2), address(merklRewardsDistributor), 10_000e18);
        deal(address(DEBT2), address(merklRewardsDistributor), 10_000e6);

        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new MockMultiTokenOpalAdapter("BASE_MOCK.1");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false));
        vm.stopPrank();
    }

    function getImmutableArgs() internal view returns (bytes memory) {
        return adapterImpl.encodeImmutableArgs(
            address(ASSET1), address(ASSET2), address(DEBT1), address(DEBT2), DEFAULT_GROUP_ID
        );
    }

    function checkExpectedBs(uint256 assetAmount1, uint256 assetAmount2, uint256 debtAmount1, uint256 debtAmount2)
        internal
        view
    {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        assertEq(totalAssets.length, 2);
        assertEq(totalAssets[0], assetAmount1);
        assertEq(totalAssets[1], assetAmount2);
        assertEq(totalLiabilities.length, 2);
        assertEq(totalLiabilities[0], debtAmount1);
        assertEq(totalLiabilities[1], debtAmount2);
    }
}

contract OpalAdapterBaseTestAdmin is OpalAdapterBaseTestBase {
    event Initialized();
    event SetDeprecated(bool indexed value);

    function test_initialize_success() public {
        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        vm.expectEmit(address(adapter));
        emit Initialized();
        adapter.initialize(abi.encode(alice, 123, false));

        assertEq(adapter.owner(), alice);
        assertEq(adapter.maxSafeLtv(), 123);
        assertTrue(adapter.isApprovedBundler(manager));
        assertFalse(adapter.isApprovedBundler(origamiMultisig));
    }

    function test_initialize_fail_badOwner() public {
        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        adapter.initialize(abi.encode(address(0), 123, false));
    }

    function test_initialize_fail_badBundler() public {
        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(0), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.InitializeFailed.selector));
        adapter.initialize(abi.encode(origamiMultisig, 123, false));
    }

    function test_initialize_fail_noInit() public {
        adapterImpl = new MockMultiTokenOpalAdapterNoInit("NO_INIT.1");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapterNoInit(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.InitializeFailed.selector));
        adapter.initialize(abi.encode(alice, 123, false));
    }

    function test_initialize_impl_fail() public {
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.InitializeFailed.selector));
        adapterImpl.initialize("");
    }

    function test_initialize_fail_alreadyInitialized() public {
        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );
        adapter.initialize(abi.encode(alice, 123, false));

        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.InitializeFailed.selector));
        adapter.initialize(abi.encode(bob, 456, false));
    }

    function test_initialize_fail_badInitArgs() public {
        vm.startPrank(address(manager));
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1,A2] / [D1,D2]", getImmutableArgs())
        );

        vm.expectRevert();
        adapter.initialize(abi.encode(123)); // missing owner
    }

    function test_description() public {
        vm.startPrank(address(manager));
        bytes32 maxDescription = 0x5454545454545454545454545454545454545454545454545454545454545454; // 32 bytes filled
        // with `T`
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), maxDescription, getImmutableArgs())
        );
        assertEq(adapter.description(), "TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT");

        // A 'null' in the middle shortcuts the string (see solday LibString.fromSmallString)
        bytes32 maxDescription2 = 0x5454545454545454545454545454540054545454545454545454545454545454; // 32 bytes filled
        // with `T`
        adapter = MockMultiTokenOpalAdapter(
            adapterFactory.create(address(adapterImpl), address(manager), maxDescription2, getImmutableArgs())
        );
        assertEq(adapter.description(), "TTTTTTTTTTTTTTT");
    }

    function test_impl_construction() public view {
        assertEq(adapterImpl.implTypeAndVersion(), "BASE_MOCK.1");
        assertEq(adapterImpl.bundler(), address(0)); // transient

        // All jibberish since it's implementation not the clone
        assertNotEq(adapterImpl.manager(), manager);
        assertNotEq(adapterImpl.description(), "[A1,A2] / [D1,D2]");
        assertEq(adapterImpl.owner(), address(0));
        assertEq(adapterImpl.maxSafeLtv(), 0);
        assertFalse(adapterImpl.isDeprecated());

        (address[] memory assetTokens, address[] memory liabilityTokens) = adapterImpl.tokens();
        assertEq(assetTokens.length, 2);
        assertNotEq(assetTokens[0], address(ASSET1));
        assertNotEq(assetTokens[1], address(ASSET2));
        assertEq(liabilityTokens.length, 2);
        assertNotEq(liabilityTokens[0], address(DEBT1));
        assertNotEq(liabilityTokens[1], address(DEBT2));

        checkExpectedBs(0, 0, 0, 0);
    }

    function test_initialization() public view {
        assertEq(adapter.implTypeAndVersion(), "BASE_MOCK.1");
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.manager(), manager);
        assertEq(adapter.description(), "[A1,A2] / [D1,D2]");
        assertEq(adapter.owner(), origamiMultisig);
        assertEq(adapter.maxSafeLtv(), MAX_SAFE_LTV);
        assertFalse(adapter.isDeprecated());

        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        assertEq(assetTokens.length, 2);
        assertEq(assetTokens[0], address(ASSET1));
        assertEq(assetTokens[1], address(ASSET2));
        assertEq(liabilityTokens.length, 2);
        assertEq(liabilityTokens[0], address(DEBT1));
        assertEq(liabilityTokens[1], address(DEBT2));

        checkExpectedBs(0, 0, 0, 0);
    }

    function test_setDeprecated() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit SetDeprecated(true);
        adapter.setDeprecated(true);
        assertTrue(adapter.isDeprecated());
        vm.expectEmit(address(adapter));
        emit SetDeprecated(false);
        adapter.setDeprecated(false);
        assertFalse(adapter.isDeprecated());
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IOpalAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(adapter.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OpalAdapterBaseTestAccess is OpalAdapterBaseTestBase {
    function test_access_setDeprecated() public {
        expectElevatedAccess();
        adapter.setDeprecated(true);
    }

    function test_access_erc20Approve() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.erc20Approve(address(ASSET1), bob, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.erc20Approve(address(ASSET1), bob, 0);
    }

    function test_access_merklClaim() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.merklClaim(alice, mkArray(alice), mkArray(0), new bytes32[][](1), alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.merklClaim(alice, mkArray(alice), mkArray(0), new bytes32[][](1), alice);
    }
}

contract OpalAdapterBaseTestBundlerActions is OpalAdapterBaseTestBase {
    function test_erc20Approve_failBadToken() public {
        vm.startPrank(manager);
        vm.expectRevert("Address: call to non-contract");
        adapter.erc20Approve(bob, bob, 1e18);
    }

    function test_erc20Approve_success() public {
        vm.startPrank(manager);

        adapter.erc20Approve(address(ASSET1), alice, type(uint256).max);
        assertEq(ASSET1.allowance(address(adapter), alice), type(uint256).max);

        adapter.erc20Approve(address(ASSET1), alice, 1e18);
        assertEq(ASSET1.allowance(address(adapter), alice), 1e18);

        deal(address(ASSET1), address(adapter), 100e18);
        vm.startPrank(alice);
        ASSET1.transferFrom(address(adapter), alice, 0.25e18);
        assertEq(ASSET1.balanceOf(alice), 0.25e18);
        assertEq(ASSET1.balanceOf(address(adapter)), 99.75e18);
        assertEq(ASSET1.allowance(address(adapter), alice), 0.75e18);

        vm.startPrank(manager);
        adapter.erc20Approve(address(ASSET1), alice, 0);
        assertEq(ASSET1.allowance(address(adapter), alice), 0);
    }

    function test_merklClaim_no_inputs() public {
        vm.startPrank(manager);
        adapter.merklClaim(
            address(merklRewardsDistributor), new address[](0), new uint256[](0), new bytes32[][](0), alice
        );
    }

    function test_merklClaim_differentRecipient() public {
        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(ASSET2);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e6;
        adapter.merklClaim(address(merklRewardsDistributor), tokens, amounts, new bytes32[][](0), alice);

        assertEq(ASSET2.balanceOf(alice), 123e6);
    }

    function test_merklClaim_sameRecipient() public {
        vm.startPrank(manager);
        address[] memory tokens = new address[](1);
        tokens[0] = address(ASSET2);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123e6;
        adapter.merklClaim(address(merklRewardsDistributor), tokens, amounts, new bytes32[][](0), address(adapter));
        assertEq(ASSET2.balanceOf(address(adapter)), 123e6);
    }

    function test_merklClaim_zeroAmount() public {
        vm.startPrank(manager);
        address[] memory tokens = new address[](2);
        tokens[0] = address(DEBT2);
        tokens[1] = address(ASSET2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 123e6;
        adapter.merklClaim(address(merklRewardsDistributor), tokens, amounts, new bytes32[][](0), address(adapter));
        assertEq(DEBT2.balanceOf(address(adapter)), 0);
        assertEq(ASSET2.balanceOf(address(adapter)), 123e6);
    }
}
