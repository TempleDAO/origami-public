pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { LibString } from "solady/utils/LibString.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";

import { OpalTestSetup } from "test/foundry/unit/investments/opal/OpalTestSetup.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiEnumerableMapLib } from "contracts/libraries/OrigamiEnumerableMapLib.sol";
import {
    MockMultiTokenOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMultiTokenOpalAdapter.m.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import {
    OrigamiTokenizedBalanceSheetTestUtils
} from "test/foundry/unit/investments/tokenizedBalanceSheet/OrigamiTokenizedBalanceSheetTestUtils.t.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import {
    MockMoneyMarketOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockMoneyMarketOpalAdapter.m.sol";
import { stdError } from "forge-std/StdError.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { OrigamiBundlerPluginMultiAccess } from "contracts/common/bundler/plugins/OrigamiBundlerPluginMultiAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    MockNonImmutableOpalAdapter
} from "test/foundry/mocks/investments/opal/adapters/MockNonImmutableOpalAdapter.m.sol";
import { DummyMintableTokenPermissionless } from "contracts/test/common/DummyMintableTokenPermissionless.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

contract OpalManagerTestBase is OpalTestSetup, OrigamiTokenizedBalanceSheetTestUtils, OrigamiBundlerTestUtils {
    MockMultiTokenOpalAdapter internal adapterImpl;
    MockMoneyMarketOpalAdapter internal adapterImpl2;
    address[] adapters;

    address internal ghostAddy = makeAddr("ghost");

    OrigamiBundlerPluginMultiAccess internal plugin;

    function setUp() public virtual override {
        super.setUp();

        plugin = new OrigamiBundlerPluginMultiAccess(origamiMultisig);
        vm.label(address(plugin), "plugin");

        vm.startPrank(origamiMultisig);
        adapterImpl = new MockMultiTokenOpalAdapter("MOCK.1");
        adapterFactory.addImplementation(address(adapterImpl));

        adapterImpl2 = new MockMoneyMarketOpalAdapter("MM_MOCK.1");
        adapterFactory.addImplementation(address(adapterImpl2));

        setExplicitAccess(manager, overlord, IOrigamiBundler.multicall.selector, true);
        vm.stopPrank();
    }

    function getVault() internal view override returns (IOrigamiTokenizedBalanceSheetVault) {
        return vault;
    }

    struct AdapterConfig {
        address asset1;
        uint256 asset1Balance;
        address asset2;
        uint256 asset2Balance;
        address liability1;
        uint256 liability1Balance;
        address liability2;
        uint256 liability2Balance;
        bytes32 groupId;
    }

    function mkArray(AdapterConfig memory v1, AdapterConfig memory v2)
        internal
        pure
        returns (AdapterConfig[] memory arr)
    {
        arr = new AdapterConfig[](2);
        arr[0] = v1;
        arr[1] = v2;
    }

    function mkArray(AdapterConfig memory v1, AdapterConfig memory v2, AdapterConfig memory v3)
        internal
        pure
        returns (AdapterConfig[] memory arr)
    {
        arr = new AdapterConfig[](3);
        arr[0] = v1;
        arr[1] = v2;
        arr[2] = v3;
    }

    function addAdapters(AdapterConfig[] memory adapterConfigs, uint256 cap) internal {
        vm.startPrank(origamiMultisig);
        for (uint256 i; i < adapterConfigs.length; ++i) {
            string memory description = LibString.concat("ADAPTER.", LibString.toString(i));
            AdapterConfig memory config = adapterConfigs[i];
            address instance = manager.addAdapter(
                address(adapterImpl),
                LibString.toSmallString(description),
                adapterImpl.encodeImmutableArgs(
                    config.asset1, config.asset2, config.liability1, config.liability2, config.groupId
                ),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
            adapters.push(instance);
            vm.label(instance, description);

            MockMultiTokenOpalAdapter(instance)
                .setAmounts(
                    _mkBalancesArray(config.asset1, config.asset1Balance, config.asset2, config.asset2Balance),
                    _mkBalancesArray(
                        config.liability1, config.liability1Balance, config.liability2, config.liability2Balance
                    )
                );

            MockMultiTokenOpalAdapter(instance)
                .setJoinExitCaps(
                    _mkCapArray(cap, config.asset1, config.asset2),
                    _mkCapArray(cap, config.liability1, config.liability2),
                    _mkCapArray(cap, config.asset1, config.asset2),
                    _mkCapArray(cap, config.liability1, config.liability2)
                );
        }
        vm.stopPrank();
    }

    function _adjustCapForTokenDecimals(uint256 capWei, address token)
        private
        view
        returns (uint256 capInTokenDecimals)
    {
        if (capWei == type(uint256).max) return capWei;
        if (token == address(0)) return 0;

        // Scale down if needed
        return capWei * (10 ** IERC20Metadata(token).decimals()) / 1e18;
    }

    function _mkCapArray(uint256 capWei, address token1, address token2)
        private
        view
        returns (uint256[] memory result)
    {
        uint256 cap1 = _adjustCapForTokenDecimals(capWei, token1);
        uint256 cap2 = _adjustCapForTokenDecimals(capWei, token2);
        if (token2 != address(0)) return mkArray(cap1, cap2);
        if (token1 != address(0)) return mkArray(cap1);
        return new uint256[](0);
    }

    function _mkBalancesArray(address token1, uint256 token1Balance, address token2, uint256 token2Balance)
        private
        pure
        returns (uint256[] memory result)
    {
        if (token2 != address(0)) return mkArray(token1Balance, token2Balance);
        if (token1 != address(0)) return mkArray(token1Balance);
        return new uint256[](0);
    }

    function getImmutableArgs() internal view returns (bytes memory) {
        return adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID);
    }

    function getInitArgs() internal view returns (bytes memory) {
        return abi.encode(origamiMultisig, 0.85e18);
    }

    function addTwoMMAdapters()
        internal
        returns (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2)
    {
        vm.startPrank(origamiMultisig);
        adapter1 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "MM_TEST.1",
                adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );
        deal(DEBT1, address(adapter1.mockMorpho()), 1_000_000e18, true);

        adapter2 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "MM_TEST.2",
                adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );
        deal(DEBT1, address(adapter2.mockMorpho()), 1_000_000e18, true);
        vm.stopPrank();
    }

    function addThreeMMAdapters()
        internal
        returns (
            MockMoneyMarketOpalAdapter adapter1,
            MockMoneyMarketOpalAdapter adapter2,
            MockMoneyMarketOpalAdapter adapter3
        )
    {
        vm.startPrank(origamiMultisig);
        adapter1 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "TEST.1",
                adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );
        deal(DEBT1, address(adapter1.mockMorpho()), 1_000_000e18, true);

        adapter2 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "TEST.2",
                adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );
        deal(DEBT1, address(adapter2.mockMorpho()), 1_000_000e18, true);

        adapter3 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "TEST.3",
                adapterImpl2.encodeImmutableArgs(ASSET2, DEBT2, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );
        deal(DEBT2, address(adapter3.mockMorpho()), 1_000_000e18, true);
        vm.stopPrank();
    }

    function supplyAndBorrow(MockMoneyMarketOpalAdapter adapter, uint256 supply, uint256 borrow) internal {
        vm.startPrank(address(manager));
        deal(address(adapter.collateralToken()), address(adapter), supply, true);
        adapter.supplyCollateral(supply, "");
        adapter.borrow(borrow, ghostAddy);
        vm.stopPrank();
    }

    function getBalance(uint256 index, address token) internal view returns (uint256 amount) {
        amount = 100e18 * (index + 1);
        if (token == ASSET1) return amount + 51e18;
        if (token == ASSET1_6DP) return amount / 1e12 + 51e6;
        if (token == ASSET2) return amount + 52e18;
        if (token == ASSET3) return amount + 53e18;
        if (token == ASSET4) return amount + 54e18;
        if (token == ASSET5) return amount + 55e18;
        if (token == ASSET6) return amount + 56e18;

        if (token == DEBT1) return amount + 21e18;
        if (token == DEBT1_6DP) return amount / 1e12 + 21e6;
        if (token == DEBT2) return amount + 22e18;
        if (token == DEBT3) return amount + 23e18;
        if (token == DEBT4) return amount + 24e18;
        if (token == DEBT5) return amount + 25e18;
        if (token == DEBT6) return amount + 26e18;
    }

    function mkAdapterConfig(uint256 index, address a1, address a2, address d1, address d2, bytes32 groupId)
        internal
        view
        returns (AdapterConfig memory config)
    {
        config.asset1 = a1;
        config.asset1Balance = getBalance(index, a1);
        config.asset2 = a2;
        config.asset2Balance = getBalance(index, a2);
        config.liability1 = d1;
        config.liability1Balance = getBalance(index, d1);
        config.liability2 = d2;
        config.liability2Balance = getBalance(index, d2);
        config.groupId = groupId;
    }

    function matchToken(address t, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability k, uint256 i) internal view {
        (IOrigamiTokenizedBalanceSheetVault.AssetOrLiability kind, uint256 index) = manager.matchToken(t);
        assertEq(uint256(kind), uint256(k));
        assertEq(index, i);
    }
}

contract OpalManagerTestAdmin is OpalManagerTestBase {
    function test_initialization() public view {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(address(manager.adapterFactory()), address(adapterFactory));
        assertEq(manager.joinFeeBps(), 0);
        assertEq(manager.exitFeeBps(), 0);
        assertEq(manager.MAX_FEE_BPS(), 330);
        assertEq(manager.MAX_ADAPTERS(), 10);
        assertEq(manager.MAX_TOKENS(), 10);

        assertEq(manager.areJoinsPaused(), false);
        assertEq(manager.areExitsPaused(), false);

        expectArr(manager.assetTokens());
        expectArr(manager.liabilityTokens());

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets);
        expectArr(combinedLiabilities);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 0);

        (combinedAssets, combinedLiabilities) = manager.maxJoin();
        expectArr(combinedAssets);
        expectArr(combinedLiabilities);
        (combinedAssets, combinedLiabilities) = manager.maxExit();
        expectArr(combinedAssets);
        expectArr(combinedLiabilities);

        assertEq(manager.adapters().length, 0);
        assertEq(manager.adaptersWithToken(address(ASSET1)).length, 0);
        assertFalse(manager.isApprovedPlugin(address(plugin)));
        assertFalse(manager.approvedPlugins(address(plugin)));
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }

    function test_setFees_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit IOpalManager.FeeBpsSet(123, 330);
        manager.setFees(123, 330);
        assertEq(manager.joinFeeBps(), 123);
        assertEq(manager.exitFeeBps(), 330);
    }

    function test_setFees_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setFees(331, 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setFees(123, 331);

        vm.expectEmit(address(manager));
        emit IOpalManager.FeeBpsSet(330, 330);
        manager.setFees(330, 330);
    }

    function test_setPluginApproved() public {
        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(manager), true);
        deal(ASSET1, address(plugin), 100e18);

        Call[] memory bundle =
            mkArray(createCall(plugin, abi.encodeCall(IOrigamiBundlerPlugin.erc20Transfer, (ASSET1, alice, 100e18))));

        // No access initially
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.InvalidPlugin.selector, address(plugin)));
        manager.multicall(bundle);
        assertEq(IERC20(ASSET1).balanceOf(alice), 0);

        {
            vm.expectEmit(address(manager));
            emit IOpalManager.PluginApprovedSet(address(plugin), true);
            manager.setPluginApproved(address(plugin), true);
            assertTrue(manager.isApprovedPlugin(address(plugin)));
            assertTrue(manager.approvedPlugins(address(plugin)));
        }

        manager.multicall(bundle);
        assertEq(IERC20(ASSET1).balanceOf(alice), 100e18);

        {
            vm.expectEmit(address(manager));
            emit IOpalManager.PluginApprovedSet(address(plugin), false);
            manager.setPluginApproved(address(plugin), false);
            assertFalse(manager.isApprovedPlugin(address(plugin)));
            assertFalse(manager.approvedPlugins(address(plugin)));
        }

        // Can't call this plugin again now
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.InvalidPlugin.selector, address(plugin)));
        manager.multicall(bundle);
    }

    function test_setPaused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);

        IOrigamiManagerPausable.Paused memory value = IOrigamiManagerPausable.Paused(true, true);
        emit IOrigamiManagerPausable.PausedSet(value);
        manager.setPaused(value);

        assertTrue(manager.areJoinsPaused());
        assertTrue(manager.areExitsPaused());
    }

    function test_setPauser() public {
        vm.startPrank(origamiMultisig);

        emit IOrigamiManagerPausable.PauserSet(alice, true);
        manager.setPauser(alice, true);
        assertEq(manager.isPauser(alice), true);

        emit IOrigamiManagerPausable.PauserSet(alice, false);
        manager.setPauser(alice, false);
        assertEq(manager.isPauser(alice), false);
    }

    // multicall() tested in another suite
}

contract OpalManagerTestAccess is OpalManagerTestBase {
    function test_addAdapter_access() public {
        expectElevatedAccess();
        manager.addAdapter(alice, "", "", "");
    }

    function test_removeAdapter_access() public {
        expectElevatedAccess();
        manager.removeAdapter(alice);
    }

    function test_multicall_access() public {
        expectElevatedAccess();
        manager.multicall(new Call[](0));
    }

    function test_setPluginApproved_access() public {
        expectElevatedAccess();
        manager.setPluginApproved(alice, true);
    }

    function test_setFees_access() public {
        expectElevatedAccess();
        manager.setFees(0, 0);
    }

    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 0);
    }

    function test_join_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.join(mkArray(0, 0), mkArray(0, 0), alice, mkBsData(mkArray(0, 0), mkArray(0, 0), ""));

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.join(mkArray(0, 0), mkArray(0, 0), alice, mkBsData(mkArray(0, 0), mkArray(0, 0), ""));
    }

    function test_exit_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.exit(mkArray(0, 0), mkArray(0, 0), alice, mkBsData(mkArray(0, 0), mkArray(0, 0), ""));

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.exit(mkArray(0, 0), mkArray(0, 0), alice, mkBsData(mkArray(0, 0), mkArray(0, 0), ""));
    }

    function test_setPauser_access() public {
        expectElevatedAccess();
        manager.setPauser(alice, true);
    }

    function test_setPaused_access() public {
        expectElevatedAccess();
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
    }
}

contract OpalManagerTestAddAdapters is OpalManagerTestBase {
    event AdapterAdded(
        address newAdapter,
        address indexed implementation,
        bytes32 indexed implTypeAndVersion,
        address indexed manager,
        bytes32 description
    );
    event Initialized();
    event AdapterAdded(address indexed adapter);

    function test_addAdapter_fail_badImpl() public {
        // No immutable args, so it has bad aseets/liabilities.
        vm.startPrank(origamiMultisig);
        bytes memory immutableArgs = "";
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);
    }

    function test_addAdapter_success_noAssets() public {
        vm.startPrank(origamiMultisig);
        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(address(0), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        expectArr(manager.assetTokens());
        expectArr(manager.liabilityTokens(), DEBT1);
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(new uint256[](0), mkArray(DEBT1))));
    }

    function test_addAdapter_success_noLiabilities() public {
        vm.startPrank(origamiMultisig);
        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, address(0), address(0), address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        expectArr(manager.assetTokens(), ASSET1);
        expectArr(manager.liabilityTokens());
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(mkArray(ASSET1), new uint256[](0))));
    }

    function test_addAdapter_fail_noAssetsOrLiabilities() public {
        vm.startPrank(origamiMultisig);
        bytes memory immutableArgs =
            adapterImpl.encodeImmutableArgs(address(0), address(0), address(0), address(0), DEFAULT_GROUP_ID);
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);
    }

    function test_addAdapter_fail_bothAssetAndLiability() public {
        vm.startPrank(origamiMultisig);
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false);

        // cant be an asset and liability
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, ASSET1, DEBT2, DEFAULT_GROUP_ID);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, ASSET1));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);

        // ok
        immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID);
        manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            immutableArgs,
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );

        immutableArgs = adapterImpl.encodeImmutableArgs(ASSET4, ASSET5, ASSET2, DEBT2, DEFAULT_GROUP_ID);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, ASSET2));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);
    }

    function test_addAdapter_fail_duplicateTokens() public {
        vm.startPrank(origamiMultisig);
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT1, DEFAULT_GROUP_ID);
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, DEBT1));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);

        immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET1, DEBT1, DEBT2, DEFAULT_GROUP_ID);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, ASSET1));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);
    }

    function test_addAdapter_fail_max_adapters() public {
        vm.startPrank(origamiMultisig);
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false);
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID);

        for (uint256 i; i < 11; ++i) {
            if (i == 10) {
                vm.expectRevert(abi.encodeWithSelector(EnumerableSetLib.ExceedsCapacity.selector));
            }

            manager.addAdapter(address(adapterImpl), "TEST", immutableArgs, initArgs);

            if (i < 10) {
                assertEq(manager.adapters().length, i + 1);
            }
        }
    }

    function test_addAdapter_fail_badGroupIds() public {
        vm.startPrank(origamiMultisig);
        bytes memory initArgs = adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, true);

        // MockMultiTokenOpalAdapter has a hack for 2 assets
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT1, DEFAULT_GROUP_ID);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);

        // MockMultiTokenOpalAdapter has a hack for 1 asset and 1 liability
        immutableArgs = adapterImpl.encodeImmutableArgs(ASSET1, address(0), DEBT1, address(0), DEFAULT_GROUP_ID);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.addAdapter(address(adapterImpl), "TEST.1", immutableArgs, initArgs);
    }

    function test_addAdapter_success_oneAdapter() public {
        vm.startPrank(origamiMultisig);
        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter1, address(adapterImpl), "MOCK.1", address(manager), "TEST.1");
        vm.expectEmit(expectedAdapter1);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter1);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        expectArr(manager.adaptersWithToken(ASSET1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET3));
        expectArr(manager.adaptersWithToken(ASSET4));
        expectArr(manager.adaptersWithToken(DEBT1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT3));
        expectArr(manager.adaptersWithToken(DEBT4));

        expectArr(manager.assetTokens(), ASSET1, ASSET2);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);

        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18, 52e18);
        expectArr(combinedLiabilities, 21e18, 22e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));

        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(combinedAssets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(mkArray(ASSET1, ASSET2), mkArray(DEBT1, DEBT2))));
    }

    function test_addAdapter_success_twoDistinctAdapters() public {
        vm.startPrank(origamiMultisig);

        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter1, address(adapterImpl), "MOCK.1", address(manager), "TEST.1");
        vm.expectEmit(expectedAdapter1);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter1);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address expectedAdapter2 = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter2, address(adapterImpl), "MOCK.1", address(manager), "TEST.2");
        vm.expectEmit(expectedAdapter2);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter2);
        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET3, ASSET4, DEBT3, DEBT4, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance2, expectedAdapter2);
        expectArr(manager.adapters(), expectedAdapter1, expectedAdapter2);
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(53e18, 54e18), mkArray(23e18, 24e18));

        expectArr(manager.adaptersWithToken(ASSET1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET3), expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET4), expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT3), expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT4), expectedAdapter2);

        expectArr(manager.assetTokens(), ASSET1, ASSET2, ASSET3, ASSET4);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2, DEBT3, DEBT4);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET3, 2, ASSET4, 3);
        expectArr(liabilityToCombinedIndexMap, DEBT3, 2, DEBT4, 3);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET4).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18, 52e18, 53e18, 54e18);
        expectArr(combinedLiabilities, 21e18, 22e18, 23e18, 24e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));

        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 53e18, 54e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 23e18, 24e18);
        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(ASSET1, ASSET2, ASSET3, ASSET4), mkArray(DEBT1, DEBT2, DEBT3, DEBT4)))
        );
    }

    function test_addAdapter_success_twoPartiallyOverlappingAdapters() public {
        vm.startPrank(origamiMultisig);

        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter1, address(adapterImpl), "MOCK.1", address(manager), "TEST.1");
        vm.expectEmit(expectedAdapter1);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter1);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address expectedAdapter2 = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter2, address(adapterImpl), "MOCK.1", address(manager), "TEST.2");
        vm.expectEmit(expectedAdapter2);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter2);
        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET3, ASSET1, DEBT2, DEBT4, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance2, expectedAdapter2);
        expectArr(manager.adapters(), expectedAdapter1, expectedAdapter2);
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(53e18, 51e18), mkArray(22e18, 24e18));

        expectArr(manager.adaptersWithToken(ASSET1), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET3), expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET4));
        expectArr(manager.adaptersWithToken(DEBT1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT2), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT3));
        expectArr(manager.adaptersWithToken(DEBT4), expectedAdapter2);

        expectArr(manager.assetTokens(), ASSET1, ASSET2, ASSET3);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2, DEBT4);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET3, 2, ASSET1, 0);
        expectArr(liabilityToCombinedIndexMap, DEBT2, 1, DEBT4, 2);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET1).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18 * 2, 52e18, 53e18);
        expectArr(combinedLiabilities, 21e18, 22e18 * 2, 24e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));

        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 53e18, 51e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 22e18, 24e18);
        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(ASSET1, ASSET2, ASSET3), mkArray(DEBT1, DEBT2, DEBT4)))
        );
    }

    function test_addAdapter_success_twoFullyOverlappingAdapters() public {
        vm.startPrank(origamiMultisig);

        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter1, address(adapterImpl), "MOCK.1", address(manager), "TEST.1");
        vm.expectEmit(expectedAdapter1);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter1);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address expectedAdapter2 = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter2, address(adapterImpl), "MOCK.1", address(manager), "TEST.2");
        vm.expectEmit(expectedAdapter2);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter2);
        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET2, ASSET1, DEBT2, DEBT1, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance2, expectedAdapter2);
        expectArr(manager.adapters(), expectedAdapter1, expectedAdapter2);
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(52e18, 51e18), mkArray(22e18, 21e18));

        expectArr(manager.adaptersWithToken(ASSET1), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET2), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET3));
        expectArr(manager.adaptersWithToken(ASSET4));
        expectArr(manager.adaptersWithToken(DEBT1), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT2), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT3));
        expectArr(manager.adaptersWithToken(DEBT4));

        expectArr(manager.assetTokens(), ASSET1, ASSET2);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET2, 1, ASSET1, 0);
        expectArr(liabilityToCombinedIndexMap, DEBT2, 1, DEBT1, 0);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance2), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18 * 2, 52e18 * 2);
        expectArr(combinedLiabilities, 21e18 * 2, 22e18 * 2);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));

        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 52e18, 51e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 22e18, 21e18);
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(mkArray(ASSET1, ASSET2), mkArray(DEBT1, DEBT2))));
    }

    function test_addAdapter_success_threeAdapters() public {
        // 1 & 2 partially overlapping, 3 is fully separate
        vm.startPrank(origamiMultisig);

        address expectedAdapter1 = 0x4f81992FCe2E1846dD528eC0102e6eE1f61ed3e2;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter1, address(adapterImpl), "MOCK.1", address(manager), "TEST.1");
        vm.expectEmit(expectedAdapter1);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter1);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance1, expectedAdapter1);
        expectArr(manager.adapters(), expectedAdapter1);
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address expectedAdapter2 = 0xCB6f5076b5bbae81D7643BfBf57897E8E3FB1db9;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter2, address(adapterImpl), "MOCK.1", address(manager), "TEST.2");
        vm.expectEmit(expectedAdapter2);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter2);
        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET2, ASSET3, DEBT4, DEBT1, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance2, expectedAdapter2);
        expectArr(manager.adapters(), expectedAdapter1, expectedAdapter2);
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(52e18, 53e18), mkArray(24e18, 21e18));

        address expectedAdapter3 = 0xA11d35fE4b9Ca9979F2FF84283a9Ce190F60Cd00;
        vm.expectEmit(address(adapterFactory));
        emit AdapterAdded(expectedAdapter3, address(adapterImpl), "MOCK.1", address(manager), "TEST.3");
        vm.expectEmit(expectedAdapter3);
        emit Initialized();
        vm.expectEmit(address(manager));
        emit AdapterAdded(expectedAdapter3);
        address instance3 = manager.addAdapter(
            address(adapterImpl),
            "TEST.3",
            adapterImpl.encodeImmutableArgs(ASSET5, ASSET6, DEBT5, DEBT6, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        assertEq(instance3, expectedAdapter3);
        expectArr(manager.adapters(), expectedAdapter1, expectedAdapter2, expectedAdapter3);
        MockMultiTokenOpalAdapter(instance3).setAmounts(mkArray(55e18, 56e18), mkArray(25e18, 26e18));

        expectArr(manager.adaptersWithToken(ASSET1), expectedAdapter1);
        expectArr(manager.adaptersWithToken(ASSET2), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET3), expectedAdapter2);
        expectArr(manager.adaptersWithToken(ASSET4));
        expectArr(manager.adaptersWithToken(ASSET5), expectedAdapter3);
        expectArr(manager.adaptersWithToken(ASSET6), expectedAdapter3);
        expectArr(manager.adaptersWithToken(DEBT1), expectedAdapter1, expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT2), expectedAdapter1);
        expectArr(manager.adaptersWithToken(DEBT3));
        expectArr(manager.adaptersWithToken(DEBT4), expectedAdapter2);
        expectArr(manager.adaptersWithToken(DEBT5), expectedAdapter3);
        expectArr(manager.adaptersWithToken(DEBT6), expectedAdapter3);

        expectArr(manager.assetTokens(), ASSET1, ASSET2, ASSET3, ASSET5, ASSET6);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2, DEBT4, DEBT5, DEBT6);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET2, 1, ASSET3, 2);
        expectArr(liabilityToCombinedIndexMap, DEBT4, 2, DEBT1, 0);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance3);
        expectArr(assetToCombinedIndexMap, ASSET5, 3, ASSET6, 4);
        expectArr(liabilityToCombinedIndexMap, DEBT5, 3, DEBT6, 4);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET5).allowance(address(manager), instance3), type(uint256).max);
        assertEq(IERC20(ASSET6).allowance(address(manager), instance3), type(uint256).max);

        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT5).allowance(address(manager), instance3), type(uint256).max);
        assertEq(IERC20(DEBT6).allowance(address(manager), instance3), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18, 52e18 * 2, 53e18, 55e18, 56e18);
        expectArr(combinedLiabilities, 21e18 * 2, 22e18, 24e18, 25e18, 26e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 3);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 52e18, 53e18);
        expectArr(perAdapterBalanceSheet[2].assets, 55e18, 56e18);
        assertEq(perAdapterBalanceSheet.length, 3);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 24e18, 21e18);
        expectArr(perAdapterBalanceSheet[2].liabilities, 25e18, 26e18);
        assertEq(
            vault.currentTokensHash(),
            keccak256(
                abi.encode(mkArray(ASSET1, ASSET2, ASSET3, ASSET5, ASSET6), mkArray(DEBT1, DEBT2, DEBT4, DEBT5, DEBT6))
            )
        );
    }
}

contract OpalManagerTestRemoveAdapters is OpalManagerTestBase {
    event AdapterRemoved(address indexed adapter);

    function test_removeAdapter_fail_empty() public {
        vm.startPrank(origamiMultisig);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );

        MockMultiTokenOpalAdapter(instance1).setDeprecated(true);

        vm.expectRevert(abi.encodeWithSelector(IOpalManager.InvalidAdapter.selector));
        manager.removeAdapter(instance1);
    }

    function test_removeAdapter_fail_notFound() public {
        vm.startPrank(origamiMultisig);

        // Add another so it wont be empty
        {
            manager.addAdapter(
                address(adapterImpl),
                "TEST.1",
                adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
        }

        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setDeprecated(true);
        manager.removeAdapter(instance1);

        vm.expectRevert(abi.encodeWithSelector(OrigamiEnumerableMapLib.EnumerableMapKeyNotFound.selector));
        manager.removeAdapter(instance1);
    }

    function test_removeAdapter_fail_notDeprecated() public {
        vm.startPrank(origamiMultisig);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );

        vm.expectRevert(abi.encodeWithSelector(IOpalManager.AdapterStillActive.selector));
        manager.removeAdapter(instance1);
    }

    function test_removeAdapter_success_noAssets() public {
        vm.startPrank(origamiMultisig);

        // Add another so it wont be empty
        address adapterX = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET6, address(0), address(0), address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );

        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(address(0), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setDeprecated(true);

        vm.expectEmit(address(manager));
        emit AdapterRemoved(instance1);
        manager.removeAdapter(instance1);

        expectArr(manager.adapters(), adapterX);
        expectArr(manager.assetTokens(), ASSET6);
        expectArr(manager.liabilityTokens());
        expectArr(manager.adaptersWithToken(DEBT1));

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap);
        expectArr(liabilityToCombinedIndexMap);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), 0);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 0);
        expectArr(combinedLiabilities);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(perAdapterBalanceSheet[0].assets, 0);
        expectArr(perAdapterBalanceSheet[0].liabilities);
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(mkArray(ASSET6), new address[](0))));
    }

    function test_removeAdapter_success_noLiabilities() public {
        vm.startPrank(origamiMultisig);

        // Add another so it wont be empty
        address adapterX = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET6, address(0), address(0), address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );

        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET2, address(0), address(0), address(0), DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setDeprecated(true);

        vm.expectEmit(address(manager));
        emit AdapterRemoved(instance1);
        manager.removeAdapter(instance1);

        expectArr(manager.adapters(), adapterX);
        expectArr(manager.assetTokens(), ASSET6);
        expectArr(manager.liabilityTokens());
        expectArr(manager.adaptersWithToken(ASSET2));

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap);
        expectArr(liabilityToCombinedIndexMap);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), 0);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 0);
        expectArr(combinedLiabilities);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 1);
        expectArr(perAdapterBalanceSheet[0].assets, 0);
        expectArr(perAdapterBalanceSheet[0].liabilities);
        assertEq(vault.currentTokensHash(), keccak256(abi.encode(mkArray(ASSET6), new address[](0))));
    }

    function test_removeAdapter_success_fromStart() public {
        vm.startPrank(origamiMultisig);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET2, ASSET3, DEBT4, DEBT1, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(52e18, 53e18), mkArray(24e18, 21e18));

        address instance3 = manager.addAdapter(
            address(adapterImpl),
            "TEST.3",
            adapterImpl.encodeImmutableArgs(ASSET5, ASSET6, DEBT5, DEBT6, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance3).setAmounts(mkArray(55e18, 56e18), mkArray(25e18, 26e18));

        MockMultiTokenOpalAdapter(instance1).setDeprecated(true);
        vm.expectEmit(address(manager));
        emit AdapterRemoved(instance1);
        manager.removeAdapter(instance1);

        expectArr(manager.adapters(), instance2, instance3);
        expectArr(manager.assetTokens(), ASSET6, ASSET2, ASSET3, ASSET5); // order changed
        expectArr(manager.liabilityTokens(), DEBT1, DEBT6, DEBT4, DEBT5); // order changed
        expectArr(manager.adaptersWithToken(ASSET1));
        expectArr(manager.adaptersWithToken(ASSET2), instance2);
        expectArr(manager.adaptersWithToken(DEBT5), instance3);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap);
        expectArr(liabilityToCombinedIndexMap);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET2, 1, ASSET3, 2);
        expectArr(liabilityToCombinedIndexMap, DEBT4, 2, DEBT1, 0);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance3);
        expectArr(assetToCombinedIndexMap, ASSET5, 3, ASSET6, 0); // order changed
        expectArr(liabilityToCombinedIndexMap, DEBT5, 3, DEBT6, 1); // order changed

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), 0);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), 0);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), 0);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), 0);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance2), type(uint256).max);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 56e18, 52e18, 53e18, 55e18);
        expectArr(combinedLiabilities, 21e18, 26e18, 24e18, 25e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 52e18, 53e18);
        expectArr(perAdapterBalanceSheet[1].assets, 55e18, 56e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 24e18, 21e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 25e18, 26e18);

        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(ASSET6, ASSET2, ASSET3, ASSET5), mkArray(DEBT1, DEBT6, DEBT4, DEBT5)))
        );
    }

    function test_removeAdapter_success_fromMiddle() public {
        vm.startPrank(origamiMultisig);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET2, ASSET3, DEBT4, DEBT1, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(52e18, 53e18), mkArray(24e18, 21e18));

        address instance3 = manager.addAdapter(
            address(adapterImpl),
            "TEST.3",
            adapterImpl.encodeImmutableArgs(ASSET5, ASSET6, DEBT5, DEBT6, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance3).setAmounts(mkArray(55e18, 56e18), mkArray(25e18, 26e18));

        MockMultiTokenOpalAdapter(instance2).setDeprecated(true);
        vm.expectEmit(address(manager));
        emit AdapterRemoved(instance2);
        manager.removeAdapter(instance2);

        expectArr(manager.adapters(), instance1, instance3);
        expectArr(manager.assetTokens(), ASSET1, ASSET2, ASSET6, ASSET5); // order changed
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2, DEBT6, DEBT5); // order changed
        expectArr(manager.adaptersWithToken(ASSET1), instance1);
        expectArr(manager.adaptersWithToken(ASSET2), instance1);
        expectArr(manager.adaptersWithToken(ASSET3));
        expectArr(manager.adaptersWithToken(DEBT5), instance3);

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap);
        expectArr(liabilityToCombinedIndexMap);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance3);
        expectArr(assetToCombinedIndexMap, ASSET5, 3, ASSET6, 2); // order changed
        expectArr(liabilityToCombinedIndexMap, DEBT5, 3, DEBT6, 2); // order changed

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance2), 0);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), 0);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), 0);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance2), 0);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18, 52e18, 56e18, 55e18);
        expectArr(combinedLiabilities, 21e18, 22e18, 26e18, 25e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 55e18, 56e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 25e18, 26e18);

        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(ASSET1, ASSET2, ASSET6, ASSET5), mkArray(DEBT1, DEBT2, DEBT6, DEBT5)))
        );
    }

    function test_removeAdapter_success_fromEnd() public {
        vm.startPrank(origamiMultisig);
        address instance1 = manager.addAdapter(
            address(adapterImpl),
            "TEST.1",
            adapterImpl.encodeImmutableArgs(ASSET1, ASSET2, DEBT1, DEBT2, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance1).setAmounts(mkArray(51e18, 52e18), mkArray(21e18, 22e18));

        address instance2 = manager.addAdapter(
            address(adapterImpl),
            "TEST.2",
            adapterImpl.encodeImmutableArgs(ASSET2, ASSET3, DEBT4, DEBT1, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance2).setAmounts(mkArray(52e18, 53e18), mkArray(24e18, 21e18));

        address instance3 = manager.addAdapter(
            address(adapterImpl),
            "TEST.3",
            adapterImpl.encodeImmutableArgs(ASSET5, ASSET6, DEBT5, DEBT6, DEFAULT_GROUP_ID),
            adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
        );
        MockMultiTokenOpalAdapter(instance3).setAmounts(mkArray(55e18, 56e18), mkArray(25e18, 26e18));

        MockMultiTokenOpalAdapter(instance3).setDeprecated(true);
        vm.expectEmit(address(manager));
        emit AdapterRemoved(instance3);
        manager.removeAdapter(instance3);

        expectArr(manager.adapters(), instance1, instance2);
        expectArr(manager.assetTokens(), ASSET1, ASSET2, ASSET3);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT2, DEBT4);
        expectArr(manager.adaptersWithToken(ASSET1), instance1);
        expectArr(manager.adaptersWithToken(ASSET2), instance1, instance2);
        expectArr(manager.adaptersWithToken(ASSET5));
        expectArr(manager.adaptersWithToken(DEBT5));

        (
            IOpalManager.AdapterToCombinedIndexMapItem[] memory assetToCombinedIndexMap,
            IOpalManager.AdapterToCombinedIndexMapItem[] memory liabilityToCombinedIndexMap
        ) = manager.adapterDetails(instance1);
        expectArr(assetToCombinedIndexMap, ASSET1, 0, ASSET2, 1);
        expectArr(liabilityToCombinedIndexMap, DEBT1, 0, DEBT2, 1);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance2);
        expectArr(assetToCombinedIndexMap, ASSET2, 1, ASSET3, 2);
        expectArr(liabilityToCombinedIndexMap, DEBT4, 2, DEBT1, 0);

        (assetToCombinedIndexMap, liabilityToCombinedIndexMap) = manager.adapterDetails(instance3);
        expectArr(assetToCombinedIndexMap);
        expectArr(liabilityToCombinedIndexMap);

        assertEq(IERC20(ASSET1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(DEBT2).allowance(address(manager), instance1), type(uint256).max);
        assertEq(IERC20(ASSET2).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET3).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT4).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(DEBT1).allowance(address(manager), instance2), type(uint256).max);
        assertEq(IERC20(ASSET5).allowance(address(manager), instance2), 0);
        assertEq(IERC20(ASSET6).allowance(address(manager), instance2), 0);
        assertEq(IERC20(DEBT5).allowance(address(manager), instance2), 0);
        assertEq(IERC20(DEBT6).allowance(address(manager), instance2), 0);

        (uint256[] memory combinedAssets, uint256[] memory combinedLiabilities, bytes memory encodedBalanceSheetData) =
            manager.balanceSheet();
        expectArr(combinedAssets, 51e18, 52e18 * 2, 53e18);
        expectArr(combinedLiabilities, 21e18 * 2, 22e18, 24e18);

        IOpalManager.AssetsAndLiabilities[] memory perAdapterBalanceSheet =
            abi.decode(encodedBalanceSheetData, (IOpalManager.AssetsAndLiabilities[]));
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].assets, 51e18, 52e18);
        expectArr(perAdapterBalanceSheet[1].assets, 52e18, 53e18);
        assertEq(perAdapterBalanceSheet.length, 2);
        expectArr(perAdapterBalanceSheet[0].liabilities, 21e18, 22e18);
        expectArr(perAdapterBalanceSheet[1].liabilities, 24e18, 21e18);

        assertEq(
            vault.currentTokensHash(),
            keccak256(abi.encode(mkArray(ASSET1, ASSET2, ASSET3), mkArray(DEBT1, DEBT2, DEBT4)))
        );
    }
}

contract OpalManagerTestMaxJoinExit is OpalManagerTestBase {
    /*
        NO CAP
    */

    function test_maxJoin_zeroCaps_sameGroup() public {
        uint256 cap = 0;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_1"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_1")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);
    }

    function test_maxJoin_zeroCaps_differentGroups() public {
        uint256 cap = 0;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_3")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);
    }

    function test_maxJoin_zeroCaps_mixedGroup() public {
        uint256 cap = 0;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, address(0), DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET1, ASSET6, DEBT5, address(0), "GROUP_1")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap);
    }

    /*
        MAX CAP
    */

    function test_maxJoin_maxCaps_sameGroup() public {
        uint256 cap = type(uint256).max;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_1"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_1")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);
    }

    function test_maxJoin_maxCaps_differentGroups() public {
        uint256 cap = type(uint256).max;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_3")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap, cap);
    }

    function test_maxJoin_maxCaps_mixedGroup() public {
        uint256 cap = type(uint256).max;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, address(0), DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET1, ASSET6, DEBT5, address(0), "GROUP_1")
            ),
            cap
        );

        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap, cap, cap);
        expectArr(liabilities, cap, cap, cap, cap);
    }

    /*
        CAP OF 100e18
    */

    function test_maxJoin_mixedCaps_sameGroup() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_1"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_1")
            ),
            cap
        );

        // ASSET2 is in adapter 1 and 2.
        // But all adapters share the same caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap - 2, cap - 2, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, cap - 2, cap - 2, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap - 2, cap - 2, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, cap - 2, cap - 2, cap - 2, cap - 2, cap - 2);
    }

    function test_maxJoin_mixedCaps_differentGroups() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_3")
            ),
            cap
        );

        // ASSET2 is in adapter 1 and 2.
        // But all adapters have unique caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap - 2, 160.317460317460317457e18, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, 154.75113122171945701e18, cap - 2, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap - 2, 160.317460317460317457e18, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, 154.75113122171945701e18, cap - 2, cap - 2, cap - 2, cap - 2);
    }

    function test_maxJoin_mixedCaps_mixedGroup() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, address(0), DEBT4, DEBT1, "GROUP_2"),
                mkAdapterConfig(2, ASSET1, ASSET6, DEBT5, address(0), "GROUP_1")
            ),
            cap
        );

        // ASSET1 is in adapter 1 and 3 and share the same cap
        // DEBT1 is in adapter 1 and 2 but have different caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap - 2, 160.317460317460317457e18, cap - 2);
        expectArr(liabilities, 154.75113122171945701e18, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap - 2, 160.317460317460317457e18, cap - 2);
        expectArr(liabilities, 154.75113122171945701e18, cap - 2, cap - 2, cap - 2);
    }

    /*
        With a 6 DP asset - CAP OF 100e18
    */

    function test_maxJoin_6dp_mixedCaps_sameGroup() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1_6DP, ASSET2, DEBT1_6DP, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1_6DP, "GROUP_1"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_1")
            ),
            cap
        );

        // ASSET2 is in adapter 1 and 2.
        // But all adapters share the same caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap / 1e12 - 2, cap - 2, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, cap / 1e12 - 2, cap - 2, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap / 1e12 - 2, cap - 2, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, cap / 1e12 - 2, cap - 2, cap - 2, cap - 2, cap - 2);
    }

    function test_maxJoin_6dp_mixedCaps_differentGroups() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1_6DP, ASSET2, DEBT1_6DP, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1_6DP, "GROUP_2"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_3")
            ),
            cap
        );

        // ASSET2 is in adapter 1 and 2.
        // But all adapters have unique caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap / 1e12 - 2, 160.317460317460317457e18, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, uint256(154.751131221719457013e18) / 1e12 - 3, cap - 2, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap / 1e12 - 2, 160.317460317460317457e18, cap - 2, cap - 2, cap - 2);
        expectArr(liabilities, uint256(154.751131221719457013e18) / 1e12 - 3, cap - 2, cap - 2, cap - 2, cap - 2);
    }

    function test_maxJoin_6dp_mixedCaps_mixedGroup() public {
        uint256 cap = 100e18;
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1_6DP, ASSET2, DEBT1_6DP, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, address(0), DEBT4, DEBT1_6DP, "GROUP_2"),
                mkAdapterConfig(2, ASSET1_6DP, ASSET6, DEBT5, address(0), "GROUP_1")
            ),
            cap
        );

        // ASSET1 is in adapter 1 and 3 and share the same cap
        // DEBT1 is in adapter 1 and 2 but have different caps
        (uint256[] memory assets, uint256[] memory liabilities) = manager.maxJoin();
        expectArr(assets, cap / 1e12 - 2, 160.317460317460317457e18, cap - 2);
        expectArr(liabilities, uint256(154.751131221719457013e18) / 1e12 - 3, cap - 2, cap - 2, cap - 2);

        (assets, liabilities) = manager.maxExit();
        expectArr(assets, cap / 1e12 - 2, 160.317460317460317457e18, cap - 2);
        expectArr(liabilities, uint256(154.751131221719457013e18) / 1e12 - 3, cap - 2, cap - 2, cap - 2);
    }
}

contract OpalManagerTestJoin is OpalManagerTestBase {
    function test_join_failBadBalanceSheetData() public {
        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        vm.expectRevert();
        manager.join(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_join_failNoAdapters() public {
        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](0));

        vm.expectRevert(abi.encodeWithSelector(IOpalManager.InvalidAdapter.selector));
        manager.join(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_join_failWrongNumAllocations() public {
        {
            vm.startPrank(origamiMultisig);
            manager.addAdapter(
                address(adapterImpl),
                "TEST.1",
                adapterImpl.encodeImmutableArgs(address(ASSET1), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
            vm.stopPrank();
        }

        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](0));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.join(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_join_failWrongNumAssetsOrLiabilities() public {
        {
            vm.startPrank(origamiMultisig);
            manager.addAdapter(
                address(adapterImpl),
                "TEST.1",
                adapterImpl.encodeImmutableArgs(address(ASSET1), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
            vm.stopPrank();
        }

        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet.assets = new uint256[](2); // setup with wrong size
        bsData.aggregatedBalanceSheet.liabilities = new uint256[](2); // setup with wrong size
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](1));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.join(new uint256[](2), new uint256[](1), alice, bsData);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.join(new uint256[](1), new uint256[](1), alice, bsData);

        bsData.aggregatedBalanceSheet.assets = new uint256[](1); // corrected

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.join(new uint256[](1), new uint256[](2), alice, bsData);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.join(new uint256[](1), new uint256[](1), alice, bsData);

        bsData.aggregatedBalanceSheet.liabilities = new uint256[](1); // corrected

        // The perAdapterBS still isn't set up right - left up to the OpalAdapter tests to check this.
        vm.expectRevert(abi.encodeWithSelector(MockMultiTokenOpalAdapter.InvalidLengthInMock.selector, 1));
        manager.join(new uint256[](1), new uint256[](1), alice, bsData);
    }

    function test_join_zeroAssetsOrLiabilities() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(400e18));
        expectArr(liabilities, mkArray(200e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        manager.join(mkArray(0), mkArray(0), alice, bsData);

        // No change
        checkBalanceSheet(mkArray(400e18), mkArray(200e18));
    }

    function test_join_zeroExistingBalances() public {
        addTwoMMAdapters();

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(0));
        expectArr(liabilities, mkArray(0));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        manager.join(mkArray(100e18), mkArray(100e18), alice, bsData);

        // No change
        checkBalanceSheet(mkArray(0), mkArray(0));
    }

    function test_join_equalSplit_success() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(400e18));
        expectArr(liabilities, mkArray(200e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        deal(ASSET1, address(manager), 100e18, true);
        manager.join(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(500e18), mkArray(300e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 250e18);
        expectArr(adapterLiabilities, 150e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 250e18);
        expectArr(adapterLiabilities, 150e18);

        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(alice), 100e18);
    }

    function test_join_skewedSplit() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 400e18, 200e18); // 2x adapter 1

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(600e18));
        expectArr(liabilities, mkArray(300e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        deal(ASSET1, address(manager), 100e18, true);
        manager.join(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(700e18), mkArray(400e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 233.333333333333333333e18);
        expectArr(adapterLiabilities, 133.333333333333333333e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 466.666666666666666667e18);
        expectArr(adapterLiabilities, 266.666666666666666667e18);

        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(alice), 100e18);
    }

    function test_join_equalSplit_bsDoesntAddUp_underflow() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        checkBalanceSheet(mkArray(400e18), mkArray(200e18));

        // Intentionally make them not sum up
        // aggregated balances are LESS than the sum of the per adapter
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet = IOpalManager.AssetsAndLiabilities(mkArray(444e18), mkArray(200e18));
        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        perAdapterBS[0] = IOpalManager.AssetsAndLiabilities(mkArray(100e18), mkArray(100e18));
        perAdapterBS[1] = IOpalManager.AssetsAndLiabilities(mkArray(200e18), mkArray(500e18));
        bsData.perAdapterBS = abi.encode(perAdapterBS);

        vm.startPrank(address(vault));
        deal(ASSET1, address(manager), 100e18, true);

        // underflow from more per adapter bs than aggregated
        vm.expectRevert(stdError.arithmeticError);
        manager.join(mkArray(100e18), mkArray(100e18), alice, bsData);
    }

    function test_join_equalSplit_bsDoesntAddUp_leftOver() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        checkBalanceSheet(mkArray(400e18), mkArray(200e18));

        // Intentionally make them not sum up
        // aggregated balances are MORE than the sum of the per adapter
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet = IOpalManager.AssetsAndLiabilities(mkArray(444e18), mkArray(200e18));
        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        perAdapterBS[0] = IOpalManager.AssetsAndLiabilities(mkArray(100e18), mkArray(100e18));
        perAdapterBS[1] = IOpalManager.AssetsAndLiabilities(mkArray(200e18), mkArray(50e18));
        bsData.perAdapterBS = abi.encode(perAdapterBS);

        vm.startPrank(address(vault));
        deal(ASSET1, address(manager), 100e18, true);
        manager.join(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(467.567567567567567567e18), mkArray(275e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 222.522522522522522522e18);
        expectArr(adapterLiabilities, 150e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 245.045045045045045045e18);
        expectArr(adapterLiabilities, 125e18);

        // Left over in the manager...
        // This is a case to show what would happen, however the vault is TRUSTED to send the correct
        // data through.
        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 32.432432432432432433e18);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(alice), 75e18); // alice didn't receive all the debt
    }

    function test_allocateAcrossAdapters_zeroCombinedBal() public {
        addTwoMMAdapters();

        IOpalManager.AssetsAndLiabilities[] memory allocations =
            manager.allocationsAcrossAdapters(mkArray(100e18), mkArray(100e18));

        assertEq(allocations.length, 2);
        expectArr(allocations[0].assets, 0);
        expectArr(allocations[0].liabilities, 0);
        expectArr(allocations[1].assets, 0);
        expectArr(allocations[1].liabilities, 0);
    }

    function test_allocateAcrossAdapters_view() public {
        (
            MockMoneyMarketOpalAdapter adapter1,
            MockMoneyMarketOpalAdapter adapter2,
            MockMoneyMarketOpalAdapter adapter3
        ) = addThreeMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 0);
        supplyAndBorrow(adapter2, 200e18, 100e18);
        supplyAndBorrow(adapter3, 50e18, 0);

        checkBalanceSheet(mkArray(400e18, 50e18), mkArray(100e18, 0));

        IOpalManager.AssetsAndLiabilities[] memory allocations =
            manager.allocationsAcrossAdapters(mkArray(100e18, 100e18), mkArray(100e18, 100e18));

        assertEq(allocations.length, 3);
        expectArr(allocations[0].assets, 50e18);
        expectArr(allocations[0].liabilities, 0);
        expectArr(allocations[1].assets, 50e18);
        expectArr(allocations[1].liabilities, 100e18);
        expectArr(allocations[2].assets, 100e18);
        expectArr(allocations[2].liabilities, 0);
    }

    function test_allocateAcrossAdapters_revert() public {
        // Gets bubbled up correctly,.
        vm.expectRevert(abi.encodeWithSelector(IOpalManager.InvalidAdapter.selector));
        manager.allocationsAcrossAdapters(mkArray(100e18, 100e18), mkArray(100e18, 100e18));
    }
}

contract OpalManagerTestExit is OpalManagerTestBase {
    function test_exit_failBadBalanceSheetData() public {
        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        vm.expectRevert();
        manager.exit(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_exit_failNoAdapters() public {
        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](0));

        vm.expectRevert(abi.encodeWithSelector(IOpalManager.InvalidAdapter.selector));
        manager.exit(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_exit_failWrongNumAllocations() public {
        {
            vm.startPrank(origamiMultisig);
            manager.addAdapter(
                address(adapterImpl),
                "TEST.1",
                adapterImpl.encodeImmutableArgs(address(ASSET1), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
            vm.stopPrank();
        }

        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](0));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.exit(new uint256[](0), new uint256[](0), alice, bsData);
    }

    function test_exit_failWrongNumAssetsOrLiabilities() public {
        {
            vm.startPrank(origamiMultisig);
            manager.addAdapter(
                address(adapterImpl),
                "TEST.1",
                adapterImpl.encodeImmutableArgs(address(ASSET1), address(0), DEBT1, address(0), DEFAULT_GROUP_ID),
                adapterImpl.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV, false)
            );
            vm.stopPrank();
        }

        vm.startPrank(address(vault));
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet.assets = new uint256[](2); // setup with wrong size
        bsData.aggregatedBalanceSheet.liabilities = new uint256[](2); // setup with wrong size
        bsData.perAdapterBS = abi.encode(new IOpalManager.AssetsAndLiabilities[](1));

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.exit(new uint256[](2), new uint256[](1), alice, bsData);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.exit(new uint256[](1), new uint256[](1), alice, bsData);

        bsData.aggregatedBalanceSheet.assets = new uint256[](1); // corrected

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.exit(new uint256[](1), new uint256[](2), alice, bsData);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        manager.exit(new uint256[](1), new uint256[](1), alice, bsData);

        bsData.aggregatedBalanceSheet.liabilities = new uint256[](1); // corrected

        // The perAdapterBS still isn't set up right - left up to the OpalAdapter tests to check this.
        vm.expectRevert(abi.encodeWithSelector(MockMultiTokenOpalAdapter.InvalidLengthInMock.selector, 1));
        manager.exit(new uint256[](1), new uint256[](1), alice, bsData);
    }

    function test_exit_zeroAssetsOrLiabilities() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(400e18));
        expectArr(liabilities, mkArray(200e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        manager.exit(mkArray(0), mkArray(0), alice, bsData);

        // No change
        checkBalanceSheet(mkArray(400e18), mkArray(200e18));
    }

    function test_exit_zeroExistingBalances() public {
        addTwoMMAdapters();

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(0));
        expectArr(liabilities, mkArray(0));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        manager.exit(mkArray(100e18), mkArray(100e18), alice, bsData);

        // No change
        checkBalanceSheet(mkArray(0), mkArray(0));
    }

    function test_exit_equalSplit_success() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(400e18));
        expectArr(liabilities, mkArray(200e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        deal(DEBT1, address(manager), 100e18, true);
        manager.exit(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(300e18), mkArray(100e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 150e18);
        expectArr(adapterLiabilities, 50e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 150e18);
        expectArr(adapterLiabilities, 50e18);

        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 0);
        assertEq(IERC20(ASSET1).balanceOf(alice), 100e18);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(alice), 0);
    }

    function test_exit_skewedSplit() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 400e18, 200e18); // 2x adapter 1

        (uint256[] memory assets, uint256[] memory liabilities, bytes memory adapterBsData) = manager.balanceSheet();
        expectArr(assets, mkArray(600e18));
        expectArr(liabilities, mkArray(300e18));

        IOpalManager.BalanceSheetData memory bsData =
            IOpalManager.BalanceSheetData(IOpalManager.AssetsAndLiabilities(assets, liabilities), adapterBsData);

        vm.startPrank(address(vault));
        deal(DEBT1, address(manager), 100e18, true);
        manager.exit(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(500e18), mkArray(200e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 166.666666666666666667e18);
        expectArr(adapterLiabilities, 66.666666666666666667e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 333.333333333333333333e18);
        expectArr(adapterLiabilities, 133.333333333333333333e18);

        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 0);
        assertEq(IERC20(ASSET1).balanceOf(alice), 100e18);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 0);
        assertEq(IERC20(DEBT1).balanceOf(alice), 0);
    }

    function test_exit_equalSplit_bsDoesntAddUp_underflow() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        checkBalanceSheet(mkArray(400e18), mkArray(200e18));

        // Intentionally make them not sum up
        // aggregated balances are LESS than the sum of the per adapter
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet = IOpalManager.AssetsAndLiabilities(mkArray(444e18), mkArray(200e18));
        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        perAdapterBS[0] = IOpalManager.AssetsAndLiabilities(mkArray(100e18), mkArray(100e18));
        perAdapterBS[1] = IOpalManager.AssetsAndLiabilities(mkArray(200e18), mkArray(500e18));
        bsData.perAdapterBS = abi.encode(perAdapterBS);

        vm.startPrank(address(vault));
        deal(DEBT1, address(manager), 100e18, true);

        // underflow from more per adapter bs than aggregated
        vm.expectRevert(stdError.arithmeticError);
        manager.exit(mkArray(100e18), mkArray(100e18), alice, bsData);
    }

    function test_exit_equalSplit_bsDoesntAddUp_leftOver() public {
        (MockMoneyMarketOpalAdapter adapter1, MockMoneyMarketOpalAdapter adapter2) = addTwoMMAdapters();
        supplyAndBorrow(adapter1, 200e18, 100e18);
        supplyAndBorrow(adapter2, 200e18, 100e18);

        checkBalanceSheet(mkArray(400e18), mkArray(200e18));

        // Intentionally make them not sum up
        // aggregated balances are MORE than the sum of the per adapter
        IOpalManager.BalanceSheetData memory bsData;
        bsData.aggregatedBalanceSheet = IOpalManager.AssetsAndLiabilities(mkArray(444e18), mkArray(200e18));
        IOpalManager.AssetsAndLiabilities[] memory perAdapterBS = new IOpalManager.AssetsAndLiabilities[](2);
        perAdapterBS[0] = IOpalManager.AssetsAndLiabilities(mkArray(100e18), mkArray(100e18));
        perAdapterBS[1] = IOpalManager.AssetsAndLiabilities(mkArray(200e18), mkArray(50e18));
        bsData.perAdapterBS = abi.encode(perAdapterBS);

        vm.startPrank(address(vault));
        deal(DEBT1, address(manager), 100e18, true);
        manager.exit(mkArray(100e18), mkArray(100e18), alice, bsData);

        // Updated totals
        checkBalanceSheet(mkArray(332.432432432432432433e18), mkArray(125e18));

        (uint256[] memory adapterAssets, uint256[] memory adapterLiabilities) = adapter1.balanceSheet();
        expectArr(adapterAssets, 177.477477477477477478e18);
        expectArr(adapterLiabilities, 50e18);
        (adapterAssets, adapterLiabilities) = adapter2.balanceSheet();
        expectArr(adapterAssets, 154.954954954954954955e18);
        expectArr(adapterLiabilities, 75e18);

        // Left over in the manager...
        // This is a case to show what would happen, however the vault is TRUSTED to send the correct
        // data through.
        assertEq(IERC20(ASSET1).balanceOf(address(manager)), 0);
        assertEq(IERC20(ASSET1).balanceOf(alice), 67.567567567567567567e18);
        assertEq(IERC20(DEBT1).balanceOf(address(manager)), 25e18);
        assertEq(IERC20(DEBT1).balanceOf(alice), 0); // alice didn't receive all the debt
    }
}

contract OpalManagerTestView is OpalManagerTestBase {
    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOpalManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOrigamiBundler).interfaceId), true);
        assertEq(manager.supportsInterface(type(IOpalAdapter).interfaceId), false);
    }

    function test_matchToken() public {
        addAdapters(
            mkArray(
                mkAdapterConfig(0, ASSET1, ASSET2, DEBT1, DEBT2, "GROUP_1"),
                mkAdapterConfig(1, ASSET2, ASSET3, DEBT4, DEBT1, "GROUP_1"),
                mkAdapterConfig(2, ASSET5, ASSET6, DEBT5, DEBT6, "GROUP_1")
            ),
            type(uint256).max
        );

        matchToken(ASSET1, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET, 0);
        matchToken(ASSET2, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET, 1);
        matchToken(DEBT1, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY, 0);
        matchToken(DEBT2, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY, 1);

        matchToken(ASSET3, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET, 2);
        matchToken(DEBT4, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY, 2);

        matchToken(ASSET5, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET, 3);
        matchToken(ASSET6, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.ASSET, 4);
        matchToken(DEBT5, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY, 3);
        matchToken(DEBT6, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.LIABILITY, 4);

        matchToken(alice, IOrigamiTokenizedBalanceSheetVault.AssetOrLiability.INVALID, 0);
    }
}

contract OpalManagerTestNonImmutableAdapter is OpalManagerTestBase {
    function test_changingAdapter() public {
        vm.startPrank(origamiMultisig);
        MockNonImmutableOpalAdapter badAdapterImpl = new MockNonImmutableOpalAdapter("MOCK.BAD");
        adapterFactory.addImplementation(address(badAdapterImpl));

        MockMoneyMarketOpalAdapter adapter1 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "MM_TEST.1",
                adapterImpl2.encodeImmutableArgs(ASSET1, DEBT1, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );

        expectArr(manager.assetTokens(), ASSET1);
        expectArr(manager.liabilityTokens(), DEBT1);

        MockNonImmutableOpalAdapter badAdapter = MockNonImmutableOpalAdapter(
            manager.addAdapter(address(badAdapterImpl), "BAD_ADAPTER.1", "", abi.encode(origamiMultisig, ASSET6, DEBT6))
        );

        expectArr(manager.assetTokens(), ASSET1, ASSET6);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT6);

        address dummyAsset = address(new DummyMintableTokenPermissionless("dummyAsset", "dummyAsset", 18));
        vm.label(dummyAsset, "dummyAsset");
        address dummyLiability = address(new DummyMintableTokenPermissionless("dummyLiability", "dummyLiability", 18));
        vm.label(dummyLiability, "dummyLiability");
        badAdapter.setTokens(dummyAsset, dummyLiability);

        (address[] memory assetTokens, address[] memory liabilityTokens) = badAdapter.tokens();
        expectArr(assetTokens, dummyAsset);
        expectArr(liabilityTokens, dummyLiability);

        MockMoneyMarketOpalAdapter adapter3 = MockMoneyMarketOpalAdapter(
            manager.addAdapter(
                address(adapterImpl2),
                "MM_TEST.2",
                adapterImpl2.encodeImmutableArgs(ASSET2, DEBT2, DEFAULT_GROUP_ID),
                adapterImpl2.encodeInitArgs(origamiMultisig, MAX_SAFE_LTV)
            )
        );

        expectArr(manager.assetTokens(), ASSET1, ASSET6, ASSET2);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT6, DEBT2);

        adapter1.setDeprecated(true);
        badAdapter.setDeprecated(true);

        // Can't remove adapter1
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.removeAdapter(address(adapter1));

        // Can still remove the bad adapter
        manager.removeAdapter(address(badAdapter));

        // However the badAdapter's tokens are still in the combined list
        // It shows things can get out of sync and why immutability is important.
        // Since adding and whitelisting adapter implementations is multiple steps
        // owned by Origami this is an acceptable risk -- all adapters will be audited anyway.
        expectArr(manager.assetTokens(), ASSET1, ASSET6, ASSET2);
        expectArr(manager.liabilityTokens(), DEBT1, DEBT6, DEBT2);

        manager.removeAdapter(address(adapter1));
        expectArr(manager.assetTokens(), ASSET6, ASSET2);
        expectArr(manager.liabilityTokens(), DEBT6, DEBT2);

        expectArr(manager.adapters(), address(adapter3));
        expectArr(manager.adaptersWithToken(ASSET6), address(badAdapter));
        expectArr(manager.adaptersWithToken(ASSET2), address(adapter3));
        expectArr(manager.adaptersWithToken(DEBT6), address(badAdapter));
        expectArr(manager.adaptersWithToken(DEBT2), address(adapter3));
    }
}
