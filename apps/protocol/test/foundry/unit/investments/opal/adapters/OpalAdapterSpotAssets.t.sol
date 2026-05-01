pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterSpotAssets } from "contracts/investments/opal/adapters/OpalAdapterSpotAssets.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOpalAdapterSpotAssets } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterSpotAssets.sol";

contract OpalAdapterSpotAssetsTestBase is OrigamiTest {
    OpalAdapterFactory internal adapterFactory;
    OpalAdapterSpotAssets internal adapterImpl;

    OpalAdapterSpotAssets internal adapter;

    DummyMintableTokenPermissionless internal ASSET1;
    DummyMintableTokenPermissionless internal ASSET2;
    DummyMintableTokenPermissionless internal ASSET3;
    DummyMintableTokenPermissionless internal ASSET4;
    address internal manager = makeAddr("manager");

    function setUp() public {
        ASSET1 = new DummyMintableTokenPermissionless("ASSET1", "ASSET1", 18);
        vm.label(address(ASSET1), "ASSET1");
        ASSET2 = new DummyMintableTokenPermissionless("ASSET2", "ASSET2", 18);
        vm.label(address(ASSET2), "ASSET2");
        ASSET3 = new DummyMintableTokenPermissionless("ASSET3", "ASSET3", 18);
        vm.label(address(ASSET3), "ASSET3");
        ASSET4 = new DummyMintableTokenPermissionless("ASSET4", "ASSET4", 18);
        vm.label(address(ASSET4), "ASSET4");

        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new OpalAdapterSpotAssets("SPOT_ASSETS.1");
        vm.label(address(adapterImpl), "SPOT_ASSETS.1 [IMPL]");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        bytes memory immutableArgs =
            adapterImpl.encodeImmutableArgs(mkArray(address(ASSET1), address(ASSET2), address(ASSET3)));
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig);
        vm.startPrank(address(manager));
        adapter = OpalAdapterSpotAssets(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1] / []", immutableArgs)
        );
        adapter.initialize(initArgs);
        vm.stopPrank();
    }

    function checkExpectedBs(uint256[] memory expectedAssetAmounts) internal view {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        expectArr(totalAssets, expectedAssetAmounts);
        assertEq(totalLiabilities.length, 0);
    }
}

contract OpalAdapterSpotAssetsTestAdmin is OpalAdapterSpotAssetsTestBase {
    function test_initialization() public view {
        assertEq(adapter.implTypeAndVersion(), "SPOT_ASSETS.1");
        assertEq(adapter.manager(), manager);
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.description(), "[A1] / []");
        expectArr(adapter.assets(), mkArray(address(ASSET1), address(ASSET2), address(ASSET3)));
        assertEq(adapter.numAssets(), 3);

        bytes32 expectedGroupId = hex"000000000000000000000000a38d17ef017a314ccd72b8f199c0e108ef7ca04c";
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        expectArr(assetGroupIds, expectedGroupId, expectedGroupId, expectedGroupId);
        expectArr(liabilityGroupIds);

        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        expectArr(assetTokens, mkArray(address(ASSET1), address(ASSET2), address(ASSET3)));
        assertEq(liabilityTokens.length, 0);

        checkExpectedBs(mkArray(0, 0, 0));

        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.maxSafeLtv(), type(uint256).max);
        assertEq(adapter.liquidationLtv(), type(uint256).max);
        assertEq(adapter.healthFactor(), type(uint256).max);

        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxExit();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
    }

    function test_balanceSheet() public {
        ASSET1.deal(address(adapter), 420.69e18);
        ASSET2.deal(address(adapter), 123e18);
        ASSET3.deal(address(adapter), 33.33e6);
        ASSET4.deal(address(adapter), 999e18);
        checkExpectedBs(mkArray(420.69e18, 123e18, 33.33e6));
    }

    function test_adapterInit_failZeroAssets() public {
        vm.startPrank(address(manager));
        bytes memory immutableArgs = abi.encodePacked(uint8(0));
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig);
        adapter = OpalAdapterSpotAssets(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1] / []", immutableArgs)
        );
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.initialize(initArgs);
    }

    function test_adapterInit_failZeroAssetAddr() public {
        vm.startPrank(address(manager));

        bytes memory immutableArgs = abi.encodePacked(uint8(1), address(0));
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig);

        adapter = OpalAdapterSpotAssets(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1] / []", immutableArgs)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(0)));
        adapter.initialize(initArgs);
    }

    function test_adapterInit_failTooManyAssets() public {
        vm.startPrank(address(manager));

        bytes memory immutableArgs = abi.encodePacked(uint8(11));
        for (uint256 i; i < 11; ++i) {
            immutableArgs = bytes.concat(immutableArgs, abi.encodePacked(address(uint160(i))));
        }

        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig);

        adapter = OpalAdapterSpotAssets(
            adapterFactory.create(address(adapterImpl), address(manager), "[A1] / []", immutableArgs)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.initialize(initArgs);
    }

    function test_encodeImmutableArgs_failZeroAssets() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapterImpl.encodeImmutableArgs(new address[](0));
    }

    function test_encodeImmutableArgs_failTooManyAssets() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapterImpl.encodeImmutableArgs(new address[](11));
    }

    function test_encodeImmutableArgs_failZeroAssetAddr() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(0)));
        adapterImpl.encodeImmutableArgs(new address[](1));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IOpalAdapterSpotAssets).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOpalAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(adapter.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OpalAdapterSpotAssetsTestAccess is OpalAdapterSpotAssetsTestBase {
    function test_access_join() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.join(new uint256[](0), new uint256[](0), alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.join(new uint256[](0), new uint256[](0), alice);
    }

    function test_access_exit() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.exit(new uint256[](0), new uint256[](0), alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.exit(new uint256[](0), new uint256[](0), alice);
    }
}

contract OpalAdapterSpotAssetsTestJoinExit is OpalAdapterSpotAssetsTestBase {
    function test_join_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18, 123e18), new uint256[](0), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18, 123e18, 123e18), mkArray(123e18), alice);
    }

    function test_join_fail_noAllowance() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: insufficient allowance");
        adapter.join(mkArray(123e18, 123e18, 123e18), new uint256[](0), alice);
    }

    function test_join_fail_noBalance() public {
        vm.startPrank(manager);
        ASSET1.approve(address(adapter), 123e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        adapter.join(mkArray(123e18, 123e18, 123e18), new uint256[](0), alice);
    }

    function test_join_success() public {
        vm.startPrank(manager);
        ASSET1.deal(address(manager), 123e18);
        ASSET1.approve(address(adapter), 123e18);
        ASSET2.deal(address(manager), 33e6);
        ASSET2.approve(address(adapter), 33e6);
        ASSET3.deal(address(manager), 420e18);
        ASSET3.approve(address(adapter), 420e18);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(123e18, 33e6, 420e18), new uint256[](0));
        adapter.join(mkArray(123e18, 33e6, 420e18), new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 123e18);
        assertEq(ASSET2.balanceOf(address(adapter)), 33e6);
        assertEq(ASSET3.balanceOf(address(adapter)), 420e18);
        checkExpectedBs(mkArray(123e18, 33e6, 420e18));
        assertEq(adapter.currentLtv(), 0);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxExit();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
    }

    function test_join_zeroAmount() public {
        vm.startPrank(manager);
        ASSET1.deal(address(manager), 123e18);
        ASSET1.approve(address(adapter), 123e18);
        ASSET3.deal(address(manager), 420e18);
        ASSET3.approve(address(adapter), 420e18);
        uint256[] memory joinAssets = mkArray(123e18, 0, 420e18);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(joinAssets, new uint256[](0));
        adapter.join(joinAssets, new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 123e18);
        assertEq(ASSET2.balanceOf(address(adapter)), 0);
        assertEq(ASSET3.balanceOf(address(adapter)), 420e18);
        assertEq(adapter.currentLtv(), 0);
        checkExpectedBs(mkArray(123e18, 0, 420e18));
    }

    function test_join_allZeroAmount() public {
        vm.startPrank(manager);
        uint256[] memory joinAssets = mkArray(0, 0, 0);

        adapter.join(joinAssets, new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 0);
        assertEq(ASSET2.balanceOf(address(adapter)), 0);
        assertEq(ASSET3.balanceOf(address(adapter)), 0);
        assertEq(adapter.currentLtv(), 0);
        checkExpectedBs(mkArray(0, 0, 0));
    }

    function test_exit_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18, 123e18), new uint256[](0), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18, 123e18, 123e18), mkArray(123e18, 123e18), alice);
    }

    function test_exit_fail_notEnough() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        adapter.exit(mkArray(123e18, 123e18, 123e18), new uint256[](0), alice);
    }

    function test_exit_success() public {
        vm.startPrank(manager);
        ASSET1.deal(address(manager), 123e18);
        ASSET1.approve(address(adapter), 123e18);
        ASSET2.deal(address(manager), 33e6);
        ASSET2.approve(address(adapter), 33e6);
        ASSET3.deal(address(manager), 420e18);
        ASSET3.approve(address(adapter), 420e18);
        adapter.join(mkArray(123e18, 33e6, 420e18), new uint256[](0), alice);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(33e18, 33e6, 33e18), new uint256[](0));
        adapter.exit(mkArray(33e18, 33e6, 33e18), new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 123e18 - 33e18);
        assertEq(ASSET2.balanceOf(address(adapter)), 33e6 - 33e6);
        assertEq(ASSET3.balanceOf(address(adapter)), 420e18 - 33e18);
        assertEq(adapter.currentLtv(), 0);
        checkExpectedBs(mkArray(123e18 - 33e18, 33e6 - 33e6, 420e18 - 33e18));
        assertEq(ASSET1.balanceOf(alice), 33e18);
        assertEq(ASSET2.balanceOf(alice), 33e6);
        assertEq(ASSET3.balanceOf(alice), 33e18);
        assertEq(adapter.currentLtv(), 0);

        adapter.exit(mkArray(123e18 - 33e18, 33e6 - 33e6, 420e18 - 33e18), new uint256[](0), alice);
        checkExpectedBs(mkArray(0, 0, 0));
        assertEq(adapter.currentLtv(), 0);
        assertEq(ASSET1.balanceOf(alice), 123e18);
        assertEq(ASSET2.balanceOf(alice), 33e6);
        assertEq(ASSET3.balanceOf(alice), 420e18);

        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxExit();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max, type(uint256).max, type(uint256).max);
        assertEq(liabilities.length, 0);
    }

    function test_exit_zeroAmount() public {
        vm.startPrank(manager);
        ASSET1.deal(address(manager), 123e18);
        ASSET1.approve(address(adapter), 123e18);
        ASSET2.deal(address(manager), 33e6);
        ASSET2.approve(address(adapter), 33e6);
        ASSET3.deal(address(manager), 420e18);
        ASSET3.approve(address(adapter), 420e18);
        adapter.join(mkArray(123e18, 33e6, 420e18), new uint256[](0), alice);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(0, 0, 111e18), new uint256[](0));
        adapter.exit(mkArray(0, 0, 111e18), new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 123e18);
        assertEq(ASSET2.balanceOf(address(adapter)), 33e6);
        assertEq(ASSET3.balanceOf(address(adapter)), 420e18 - 111e18);
        checkExpectedBs(mkArray(123e18, 33e6, 420e18 - 111e18));
        assertEq(ASSET1.balanceOf(alice), 0);
        assertEq(ASSET2.balanceOf(alice), 0);
        assertEq(ASSET3.balanceOf(alice), 111e18);
        assertEq(adapter.currentLtv(), 0);
    }

    function test_exit_allZeroAmount() public {
        vm.startPrank(manager);
        ASSET1.deal(address(manager), 123e18);
        ASSET1.approve(address(adapter), 123e18);
        ASSET2.deal(address(manager), 33e6);
        ASSET2.approve(address(adapter), 33e6);
        ASSET3.deal(address(manager), 420e18);
        ASSET3.approve(address(adapter), 420e18);
        adapter.join(mkArray(123e18, 33e6, 420e18), new uint256[](0), alice);

        adapter.exit(mkArray(0, 0, 0), new uint256[](0), alice);
        assertEq(ASSET1.balanceOf(address(adapter)), 123e18);
        assertEq(ASSET2.balanceOf(address(adapter)), 33e6);
        assertEq(ASSET3.balanceOf(address(adapter)), 420e18);
        checkExpectedBs(mkArray(123e18, 33e6, 420e18));
        assertEq(ASSET1.balanceOf(alice), 0);
        assertEq(ASSET2.balanceOf(alice), 0);
        assertEq(ASSET3.balanceOf(alice), 0);
        assertEq(adapter.currentLtv(), 0);
    }
}
