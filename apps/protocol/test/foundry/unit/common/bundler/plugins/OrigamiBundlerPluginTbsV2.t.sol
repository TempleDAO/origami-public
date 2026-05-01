pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiBundlerPluginTbsV2 } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsV2.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginTbsV2 } from "contracts/common/bundler/plugins/OrigamiBundlerPluginTbsV2.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OpalVault } from "contracts/investments/opal/OpalVault.sol";
import { OpalManager } from "contracts/investments/opal/OpalManager.sol";
import { OpalAdapterAaveV3 } from "contracts/investments/opal/adapters/OpalAdapterAaveV3.sol";
import { IOpalManager } from "contracts/interfaces/investments/opal/IOpalManager.sol";
import {
    ITokenizedBalanceSheetVaultV1 as ITBSV
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVaultV1.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import {
    IOrigamiBundlerPluginTbsBase
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsBase.sol";

contract OrigamiBundlerPluginTbsV2TestBase is OrigamiTest, OrigamiBundlerTestUtils {
    address internal constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant WEETH_TOKEN = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant AAVE_POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    uint8 internal constant ETH_CORRELATED_EMODE = 1;
    uint256 internal constant MAX_UR_ON_JOIN = 0.92e18; // 92% max

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterAaveV3 internal aaveAdapterImpl;
    OpalVault internal opalVault;
    OpalManager internal opalManager;

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginTbsV2 internal plugin;

    bytes32 internal tokensHash;

    function setUp() public {
        fork("mainnet", 23_617_039);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginTbsV2(origamiMultisig);

        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        aaveAdapterImpl = new OpalAdapterAaveV3("AAVE-V3.1");
        opalVault = new OpalVault(origamiMultisig, "OPAL", "OPAL", 100, origamiMultisig, address(0));
        opalManager = new OpalManager(origamiMultisig, address(opalVault), address(adapterFactory));

        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(aaveAdapterImpl));
        opalVault.setManager(address(opalManager));
        opalManager.addAdapter(
            address(aaveAdapterImpl),
            "[WEETH/WETH]",
            aaveAdapterImpl.encodeImmutableArgs(AAVE_POOL_ADDRESS_PROVIDER, mkArray(WEETH_TOKEN), WETH_TOKEN),
            aaveAdapterImpl.encodeInitArgs(origamiMultisig, ETH_CORRELATED_EMODE, MAX_UR_ON_JOIN)
        );

        plugin.setBundlerApproved(address(bundler), true);
        plugin.trustVault(address(opalVault));

        seed();
        vm.stopPrank();

        tokensHash = opalVault.currentTokensHash();
    }

    function seed() private {
        uint256 collateral = 0.250020043588251586e18;
        uint256 debt = 0.2157034215e18;
        uint256 shares = 1000 * collateral;
        deal(WEETH_TOKEN, origamiMultisig, collateral);

        IERC20(WEETH_TOKEN).approve(address(opalVault), collateral);

        IOpalManager.AssetsAndLiabilities[] memory adapterSplit = new IOpalManager.AssetsAndLiabilities[](1);
        adapterSplit[0].assets = mkArray(collateral);
        adapterSplit[0].liabilities = mkArray(debt);

        opalVault.seed(
            mkArray(collateral), mkArray(debt), shares, origamiMultisig, type(uint256).max, abi.encode(adapterSplit)
        );
    }
}

contract OrigamiBundlerPluginTbsV2TestAdmin is OrigamiBundlerPluginTbsV2TestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertFalse(plugin.isApprovedBundler(alice));
        assertTrue(plugin.isVaultTrusted(address(opalVault)));
        assertFalse(plugin.isVaultTrusted(alice));
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginTbsV2).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginMultiAccess).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(plugin.supportsInterface(type(IERC165).interfaceId));
        assertTrue(plugin.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(plugin.supportsInterface(type(IERC20).interfaceId));
    }

    function test_trustVault_basic() public {
        vm.startPrank(origamiMultisig);

        assertFalse(plugin.isVaultTrusted(alice));

        emit IOrigamiBundlerPluginTbsBase.TrustedVaultSet(alice, true);
        plugin.trustVault(alice);
        assertTrue(plugin.isVaultTrusted(alice));

        emit IOrigamiBundlerPluginTbsBase.TrustedVaultSet(alice, false);
        plugin.dontTrustVault(alice, false, 0);
        assertFalse(plugin.isVaultTrusted(alice));
    }

    function test_trustVault_withApprovals() public {
        vm.startPrank(origamiMultisig);

        deal(WEETH_TOKEN, address(plugin), 1e18);
        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.8627445160166186e18);

        // Join and exit
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);

        address[] memory approvals = plugin.getApprovedTokens(address(opalVault));
        assertEq(approvals.length, 2);

        // Has max approvals
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(address(opalVault));
        assertTrue(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Approvals were rugged correctly
        plugin.dontTrustVault(address(opalVault), true, 50_000);
        assertFalse(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);

        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 0); // no approvals
    }

    function addFakeTokens() private returns (address[] memory fakeAssets, address[] memory fakeLiabilities) {
        fakeAssets = new address[](51);
        fakeLiabilities = new address[](51);
        fakeAssets[0] = WEETH_TOKEN;
        fakeLiabilities[0] = WETH_TOKEN;
        for (uint256 i = 1; i < fakeAssets.length; ++i) {
            fakeAssets[i] = address(new MockERC20("mockAsset", "mockAsset", 18));
            fakeLiabilities[i] = address(new MockERC20("mockAsset", "mockAsset", 18));
        }

        // mock tokens()
        // and mock so the 20th item reverts when revoking approval
        vm.mockCall(
            address(address(opalVault)),
            abi.encodeWithSelector(ITBSV.tokens.selector),
            abi.encode(fakeAssets, fakeLiabilities)
        );

        deal(WEETH_TOKEN, address(plugin), 1e18);
        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.8627445160166186e18);

        // Join and exit
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);

        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 102);
    }

    function test_trustVault_manyFakeTokens_withRevoke() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(address(opalVault));
        assertTrue(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // All but the 20th item has it's approval actually rugged
        vm.mockCallRevert(fakeAssets[20], IERC20.approve.selector, "no bueno");
        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");

        // Approvals were rugged correctly
        plugin.dontTrustVault(address(opalVault), true, 50_000);
        assertFalse(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max); // revoke
        // reverted
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max); // revoke
        // reverted
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), 0);

        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 0);
    }

    function test_trustVault_manyFakeTokens_underStipend() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(address(opalVault));
        assertTrue(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Nothing was rugged because it was under the stipend
        plugin.dontTrustVault(address(opalVault), true, 1);
        assertFalse(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 0);
    }

    function test_trustVault_manyFakeTokens_noRevoke() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(address(opalVault));
        assertTrue(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        // All but the 20th item has it's approval actually rugged
        vm.mockCallRevert(fakeAssets[20], IERC20.approve.selector, "no bueno");
        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");

        // Approvals weren't rugged
        plugin.dontTrustVault(address(opalVault), false, 0);
        assertFalse(plugin.isVaultTrusted(address(opalVault)));
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 0);
    }

    function test_revokeApprovals() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[10]).allowance(address(plugin), address(opalVault)), type(uint256).max);

        vm.startPrank(origamiMultisig);
        plugin.revokeApprovals(address(opalVault), mkArray(fakeAssets[50], fakeLiabilities[10]));
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(fakeLiabilities[10]).allowance(address(plugin), address(opalVault)), 0);

        // Unchanged
        assertEq(plugin.getApprovedTokens(address(opalVault)).length, 102);
        assertEq(plugin.getApprovedTokens(address(opalVault))[101], fakeLiabilities[50]);

        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");
        vm.expectRevert("no bueno");
        plugin.revokeApprovals(address(opalVault), mkArray(fakeAssets[50], fakeLiabilities[20], fakeLiabilities[10]));
    }
}

contract OrigamiBundlerPluginTbsV2TestAccess is OrigamiBundlerPluginTbsV2TestBase {
    function test_access_trustVault() public {
        expectElevatedAccess();
        plugin.trustVault(alice);
    }

    function test_access_dontTrustVault() public {
        expectElevatedAccess();
        plugin.dontTrustVault(alice, true, 0);
    }

    function test_access_revokeApprovals() public {
        expectElevatedAccess();
        plugin.revokeApprovals(alice, mkArray(alice));
    }

    function test_access_joinWithAssetBalance() public {
        checkInvalidBundler(alice);
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
    }

    function test_access_joinWithToken() public {
        checkInvalidBundler(alice);
        plugin.joinWithToken(address(opalVault), WEETH_TOKEN, 123, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithToken(address(opalVault), WEETH_TOKEN, 123, alice, tokensHash);
    }

    function test_access_joinWithShares() public {
        checkInvalidBundler(alice);
        plugin.joinWithShares(address(opalVault), 123, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithShares(address(opalVault), 123, alice, tokensHash);
    }

    function test_access_exitWithLiabilityBalance() public {
        checkInvalidBundler(alice);
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);
    }

    function test_access_exitWithToken() public {
        checkInvalidBundler(alice);
        plugin.exitWithToken(address(opalVault), WETH_TOKEN, 123, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithToken(address(opalVault), WETH_TOKEN, 123, alice, tokensHash);
    }

    function test_access_exitWithSharesBalance() public {
        checkInvalidBundler(alice);
        plugin.exitWithSharesBalance(address(opalVault), alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithSharesBalance(address(opalVault), alice, tokensHash);
    }

    function test_access_exitWithShares() public {
        checkInvalidBundler(alice);
        plugin.exitWithShares(address(opalVault), 123, alice, tokensHash);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithShares(address(opalVault), 123, alice, tokensHash);
    }
}

contract OrigamiBundlerPluginTbsV2TestBundlerActions is OrigamiBundlerPluginTbsV2TestBase {
    function test_joinWithAssetBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithAssetBalance(alice, WEETH_TOKEN, alice, tokensHash);
    }

    function test_joinWithAssetBalance_notAsset() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotAsset.selector));
        plugin.joinWithAssetBalance(address(opalVault), USDC_TOKEN, alice, tokensHash);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotAsset.selector));
        plugin.joinWithAssetBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);
    }

    function test_joinWithAssetBalance_noBalance() public {
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
    }

    function test_joinWithAssetBalance_success() public {
        deal(WEETH_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 1000e18 + 3999);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0.862744516016618603e18);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
    }

    function test_joinWithToken_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithToken(alice, WEETH_TOKEN, 123, alice, tokensHash);
    }

    function test_joinWithToken_notAssetOrLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, USDC_TOKEN, 123, 0
            )
        );
        plugin.joinWithToken(address(opalVault), USDC_TOKEN, 123, alice, tokensHash);
    }

    function test_joinWithToken_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.joinWithToken(address(opalVault), WEETH_TOKEN, 0, alice, tokensHash);
    }

    function test_joinWithToken_success_asset() public {
        deal(WEETH_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithToken(address(opalVault), WEETH_TOKEN, 1e18, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 1000e18 + 3999);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0.862744516016618603e18);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
    }

    function test_joinWithToken_success_liability() public {
        deal(WEETH_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithToken(address(opalVault), WETH_TOKEN, 0.862744516016618603e18, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 1000e18 + 3228);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0.862744516016618603e18);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
    }

    function test_joinWithShares_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithShares(alice, 123, alice, tokensHash);
    }

    function test_joinWithShares_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.joinWithShares(address(opalVault), 0, alice, tokensHash);
    }

    function test_joinWithShares_success() public {
        deal(WEETH_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithShares(address(opalVault), 1000e18, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 1000e18);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0.8627445160166186e18);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
    }

    function test_exitWithLiabilityBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithLiabilityBalance(alice, WEETH_TOKEN, alice, tokensHash);
    }

    function test_exitWithLiabilityBalance_notLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotLiability.selector));
        plugin.exitWithLiabilityBalance(address(opalVault), USDC_TOKEN, alice, tokensHash);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotLiability.selector));
        plugin.exitWithLiabilityBalance(address(opalVault), WEETH_TOKEN, alice, tokensHash);
    }

    function test_exitWithLiabilityBalance_zeroBalance() public {
        vm.startPrank(address(bundler));
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function addTvl() private {
        vm.startPrank(address(bundler));
        deal(WEETH_TOKEN, address(plugin), 10e18);
        plugin.joinWithAssetBalance(address(opalVault), WEETH_TOKEN, origamiMultisig, tokensHash);
        vm.stopPrank();
    }

    function test_exitWithLiabilityBalance_success() public {
        addTvl();

        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.8627445160166186e18);

        vm.startPrank(address(bundler));
        plugin.exitWithLiabilityBalance(address(opalVault), WETH_TOKEN, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 289);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 1e18 - 5);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function test_exitWithToken_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithToken(alice, WEETH_TOKEN, 123, alice, tokensHash);
    }

    function test_exitWithToken_notAssetOrLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector,
                address(plugin),
                USDC_TOKEN,
                123,
                0
            )
        );
        plugin.exitWithToken(address(opalVault), USDC_TOKEN, 123, alice, tokensHash);
    }

    function test_exitWithToken_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.exitWithToken(address(opalVault), WEETH_TOKEN, 0, alice, tokensHash);
    }

    function test_exitWithToken_success_asset() public {
        addTvl();

        deal(address(opalVault), address(plugin), 1000e18 - 902);
        deal(WETH_TOKEN, address(plugin), 0.8627445160166186e18);

        vm.startPrank(address(bundler));
        plugin.exitWithToken(address(opalVault), WEETH_TOKEN, 1e18 - 5, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 1e18 - 5);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function test_exitWithToken_success_liability() public {
        addTvl();

        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.8627445160166186e18);

        vm.startPrank(address(bundler));
        plugin.exitWithToken(address(opalVault), WETH_TOKEN, 0.8627445160166186e18, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 289);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 1e18 - 5);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function test_exitWithSharesBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithSharesBalance(alice, alice, tokensHash);
    }

    function test_exitWithSharesBalance_zeroBalance() public {
        vm.startPrank(address(bundler));
        plugin.exitWithSharesBalance(address(opalVault), alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), 0);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function test_exitWithSharesBalance_success() public {
        addTvl();

        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.862744516016618601e18);

        vm.startPrank(address(bundler));
        plugin.exitWithSharesBalance(address(opalVault), alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 1e18 - 5);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }

    function test_exitWithShares_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithShares(alice, 123, alice, tokensHash);
    }

    function test_exitWithShares_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.exitWithShares(address(opalVault), 0, alice, tokensHash);
    }

    function test_exitWithShares_success() public {
        addTvl();

        deal(address(opalVault), address(plugin), 1000e18);
        deal(WETH_TOKEN, address(plugin), 0.862744516016618601e18);

        vm.startPrank(address(bundler));
        plugin.exitWithShares(address(opalVault), 1000e18, alice, tokensHash);
        assertEq(opalVault.balanceOf(alice), 0);
        assertEq(opalVault.balanceOf(address(plugin)), 0);
        assertEq(IERC20(WEETH_TOKEN).balanceOf(alice), 1e18 - 5);
        assertEq(IERC20(WETH_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(WEETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
        assertEq(IERC20(WETH_TOKEN).allowance(address(plugin), address(opalVault)), type(uint256).max);
    }
}
