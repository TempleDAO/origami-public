pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiBundlerPluginTbsV1 } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsV1.sol";
import {
    IOrigamiBundlerPluginMultiAccess
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginMultiAccess.sol";
import { OrigamiBundlerPluginTbsV1 } from "contracts/common/bundler/plugins/OrigamiBundlerPluginTbsV1.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";
import {
    ITokenizedBalanceSheetVaultV1 as ITBSV
} from "contracts/interfaces/external/tokenizedBalanceSheetVault/ITokenizedBalanceSheetVaultV1.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import {
    IOrigamiBundlerPluginTbsBase
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginTbsBase.sol";

contract OrigamiBundlerPluginTbsV1TestBase is OrigamiTest, OrigamiBundlerTestUtils {
    address internal constant HOHM_TBS = 0x1DB1591540d7A6062Be0837ca3C808aDd28844F6;
    address internal constant GOHM_TOKEN = 0x0ab87046fBb341D058F17CBC4c1133F25a20a52f;
    address internal constant USDS_TOKEN = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant WETH_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    OrigamiBundler internal bundler;
    OrigamiBundlerPluginTbsV1 internal plugin;

    function setUp() public {
        fork("mainnet", 23_617_039);
        bundler = new OrigamiBundler();
        plugin = new OrigamiBundlerPluginTbsV1(origamiMultisig);

        vm.startPrank(origamiMultisig);
        plugin.setBundlerApproved(address(bundler), true);
        plugin.trustVault(HOHM_TBS);
        vm.stopPrank();
    }
}

contract OrigamiBundlerPluginTbsV1TestAdmin is OrigamiBundlerPluginTbsV1TestBase {
    function test_initialization() public view {
        assertEq(plugin.owner(), origamiMultisig);
        assertTrue(plugin.isApprovedBundler(address(bundler)));
        assertFalse(plugin.isApprovedBundler(alice));
        assertTrue(plugin.isVaultTrusted(HOHM_TBS));
        assertFalse(plugin.isVaultTrusted(alice));
    }

    function test_supportsInterface() public view {
        assertTrue(plugin.supportsInterface(type(IOrigamiBundlerPluginTbsV1).interfaceId));
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

        deal(GOHM_TOKEN, address(plugin), 1e18);
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.72445617979953112e18);

        // Join and exit
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);

        address[] memory approvals = plugin.getApprovedTokens(HOHM_TBS);
        assertEq(approvals.length, 2);

        // Has max approvals
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(HOHM_TBS);
        assertTrue(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Approvals were rugged correctly
        plugin.dontTrustVault(HOHM_TBS, true, 50_000);
        assertFalse(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);

        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 0); // no approvals
    }

    function addFakeTokens() private returns (address[] memory fakeAssets, address[] memory fakeLiabilities) {
        fakeAssets = new address[](51);
        fakeLiabilities = new address[](51);
        fakeAssets[0] = GOHM_TOKEN;
        fakeLiabilities[0] = USDS_TOKEN;
        for (uint256 i = 1; i < fakeAssets.length; ++i) {
            fakeAssets[i] = address(new MockERC20("mockAsset", "mockAsset", 18));
            fakeLiabilities[i] = address(new MockERC20("mockAsset", "mockAsset", 18));
        }

        // mock tokens()
        // and mock so the 20th item reverts when revoking approval
        vm.mockCall(
            address(HOHM_TBS), abi.encodeWithSelector(ITBSV.tokens.selector), abi.encode(fakeAssets, fakeLiabilities)
        );

        deal(GOHM_TOKEN, address(plugin), 1e18);
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.72445617979953112e18);

        // Join and exit
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);

        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 102);
    }

    function test_trustVault_manyFakeTokens_withRevoke() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(HOHM_TBS);
        assertTrue(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // All but the 20th item has it's approval actually rugged
        vm.mockCallRevert(fakeAssets[20], IERC20.approve.selector, "no bueno");
        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");

        // Approvals were rugged correctly
        plugin.dontTrustVault(HOHM_TBS, true, 50_000);
        assertFalse(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max); // revoke reverted
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max); // revoke
        // reverted
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), 0);

        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 0);
    }

    function test_trustVault_manyFakeTokens_underStipend() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(HOHM_TBS);
        assertTrue(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Nothing was rugged because it was under the stipend
        plugin.dontTrustVault(HOHM_TBS, true, 1);
        assertFalse(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 0);
    }

    function test_trustVault_manyFakeTokens_noRevoke() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();

        // Has max approvals
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // Still has approvals
        vm.startPrank(origamiMultisig);
        plugin.trustVault(HOHM_TBS);
        assertTrue(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        // All but the 20th item has it's approval actually rugged
        vm.mockCallRevert(fakeAssets[20], IERC20.approve.selector, "no bueno");
        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");

        // Approvals weren't rugged
        plugin.dontTrustVault(HOHM_TBS, false, 0);
        assertFalse(plugin.isVaultTrusted(HOHM_TBS));
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(fakeAssets[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[20]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 0);
    }

    function test_revokeApprovals() public {
        (address[] memory fakeAssets, address[] memory fakeLiabilities) = addFakeTokens();
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(fakeLiabilities[10]).allowance(address(plugin), HOHM_TBS), type(uint256).max);

        vm.startPrank(origamiMultisig);
        plugin.revokeApprovals(HOHM_TBS, mkArray(fakeAssets[50], fakeLiabilities[10]));
        assertEq(IERC20(fakeAssets[50]).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(fakeLiabilities[10]).allowance(address(plugin), HOHM_TBS), 0);

        // Unchanged
        assertEq(plugin.getApprovedTokens(HOHM_TBS).length, 102);
        assertEq(plugin.getApprovedTokens(HOHM_TBS)[101], fakeLiabilities[50]);

        vm.mockCallRevert(fakeLiabilities[20], IERC20.approve.selector, "no bueno");
        vm.expectRevert("no bueno");
        plugin.revokeApprovals(HOHM_TBS, mkArray(fakeAssets[50], fakeLiabilities[20], fakeLiabilities[10]));
    }
}

contract OrigamiBundlerPluginTbsV1TestAccess is OrigamiBundlerPluginTbsV1TestBase {
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
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);
    }

    function test_access_joinWithToken() public {
        checkInvalidBundler(alice);
        plugin.joinWithToken(HOHM_TBS, GOHM_TOKEN, 123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithToken(HOHM_TBS, GOHM_TOKEN, 123, alice);
    }

    function test_access_joinWithShares() public {
        checkInvalidBundler(alice);
        plugin.joinWithShares(HOHM_TBS, 123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.joinWithShares(HOHM_TBS, 123, alice);
    }

    function test_access_exitWithLiabilityBalance() public {
        checkInvalidBundler(alice);
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);
    }

    function test_access_exitWithToken() public {
        checkInvalidBundler(alice);
        plugin.exitWithToken(HOHM_TBS, USDS_TOKEN, 123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithToken(HOHM_TBS, USDS_TOKEN, 123, alice);
    }

    function test_access_exitWithSharesBalance() public {
        checkInvalidBundler(alice);
        plugin.exitWithSharesBalance(HOHM_TBS, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithSharesBalance(HOHM_TBS, alice);
    }

    function test_access_exitWithShares() public {
        checkInvalidBundler(alice);
        plugin.exitWithShares(HOHM_TBS, 123, alice);

        checkInvalidBundler(origamiMultisig);
        plugin.exitWithShares(HOHM_TBS, 123, alice);
    }
}

contract OrigamiBundlerPluginTbsV1TestBundlerActions is OrigamiBundlerPluginTbsV1TestBase {
    function test_joinWithAssetBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithAssetBalance(alice, GOHM_TOKEN, alice);
    }

    function test_joinWithAssetBalance_notAsset() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotAsset.selector));
        plugin.joinWithAssetBalance(HOHM_TBS, WETH_TOKEN, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotAsset.selector));
        plugin.joinWithAssetBalance(HOHM_TBS, USDS_TOKEN, alice);
    }

    function test_joinWithAssetBalance_noBalance() public {
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
    }

    function test_joinWithAssetBalance_success() public {
        deal(GOHM_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithAssetBalance(HOHM_TBS, GOHM_TOKEN, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 268_563.409223712892520802e18);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 2973.459046646262152646e18);
        // annoying - gOHM doesn't keep it as max allowance on transferFrom
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
    }

    function test_joinWithToken_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithToken(alice, GOHM_TOKEN, 123, alice);
    }

    function test_joinWithToken_notAssetOrLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxJoinWithToken.selector, alice, WETH_TOKEN, 123, 0
            )
        );
        plugin.joinWithToken(HOHM_TBS, WETH_TOKEN, 123, alice);
    }

    function test_joinWithToken_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.joinWithToken(HOHM_TBS, GOHM_TOKEN, 0, alice);
    }

    function test_joinWithToken_success_asset() public {
        deal(GOHM_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithToken(HOHM_TBS, GOHM_TOKEN, 1e18, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 268_563.409223712892520802e18);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 2973.459046646262152646e18);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
    }

    function test_joinWithToken_success_liability() public {
        deal(GOHM_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithToken(HOHM_TBS, USDS_TOKEN, 2973.459046646262152646e18, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 268_563.409223712892520728e18);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 2973.459046646262152646e18);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
    }

    function test_joinWithShares_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.joinWithShares(alice, 123, alice);
    }

    function test_joinWithShares_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.joinWithShares(HOHM_TBS, 0, alice);
    }

    function test_joinWithShares_success() public {
        deal(GOHM_TOKEN, address(plugin), 1e18);
        vm.startPrank(address(bundler));
        plugin.joinWithShares(HOHM_TBS, 268_563.409223712892520802e18, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 268_563.409223712892520802e18);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 2973.459046646262152646e18);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max - 1e18);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
    }

    function test_exitWithLiabilityBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithLiabilityBalance(alice, GOHM_TOKEN, alice);
    }

    function test_exitWithLiabilityBalance_notLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotLiability.selector));
        plugin.exitWithLiabilityBalance(HOHM_TBS, WETH_TOKEN, alice);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.NotLiability.selector));
        plugin.exitWithLiabilityBalance(HOHM_TBS, GOHM_TOKEN, alice);
    }

    function test_exitWithLiabilityBalance_zeroBalance() public {
        vm.startPrank(address(bundler));
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithLiabilityBalance_success() public {
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.72445617979953112e18);

        vm.startPrank(address(bundler));
        plugin.exitWithLiabilityBalance(HOHM_TBS, USDS_TOKEN, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 33);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0.99e18 - 1);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithToken_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithToken(alice, GOHM_TOKEN, 123, alice);
    }

    function test_exitWithToken_notAssetOrLiability() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrigamiTokenizedBalanceSheetVault.ExceededMaxExitWithToken.selector,
                address(plugin),
                WETH_TOKEN,
                123,
                0
            )
        );
        plugin.exitWithToken(HOHM_TBS, WETH_TOKEN, 123, alice);
    }

    function test_exitWithToken_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.exitWithToken(HOHM_TBS, GOHM_TOKEN, 0, alice);
    }

    function test_exitWithToken_success_asset() public {
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.72445617979953112e18);

        vm.startPrank(address(bundler));
        plugin.exitWithToken(HOHM_TBS, GOHM_TOKEN, 0.99e18 - 1, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 271_275);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0.99e18 - 1);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithToken_success_liability() public {
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.72445617979953112e18);

        vm.startPrank(address(bundler));
        plugin.exitWithToken(HOHM_TBS, USDS_TOKEN, 2943.72445617979953112e18, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 33);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0.99e18 - 1);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithSharesBalance_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithSharesBalance(alice, alice);
    }

    function test_exitWithSharesBalance_zeroBalance() public {
        vm.startPrank(address(bundler));
        plugin.exitWithSharesBalance(HOHM_TBS, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithSharesBalance_success() public {
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.724456179799531121e18);

        vm.startPrank(address(bundler));
        plugin.exitWithSharesBalance(HOHM_TBS, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0.99e18 - 1);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }

    function test_exitWithShares_notTrusted() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPluginTbsBase.InvalidVault.selector));
        plugin.exitWithShares(alice, 123, alice);
    }

    function test_exitWithShares_zeroBalance() public {
        vm.startPrank(address(bundler));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        plugin.exitWithShares(HOHM_TBS, 0, alice);
    }

    function test_exitWithShares_success() public {
        deal(HOHM_TBS, address(plugin), 268_563.409223712892520802e18);
        deal(USDS_TOKEN, address(plugin), 2943.724456179799531121e18);

        vm.startPrank(address(bundler));
        plugin.exitWithShares(HOHM_TBS, 268_563.409223712892520802e18, alice);
        assertEq(IERC20(HOHM_TBS).balanceOf(alice), 0);
        assertEq(IERC20(HOHM_TBS).balanceOf(address(plugin)), 0);
        assertEq(IERC20(GOHM_TOKEN).balanceOf(alice), 0.99e18 - 1);
        assertEq(IERC20(USDS_TOKEN).balanceOf(alice), 0);
        assertEq(IERC20(GOHM_TOKEN).allowance(address(plugin), HOHM_TBS), 0);
        assertEq(IERC20(USDS_TOKEN).allowance(address(plugin), HOHM_TBS), type(uint256).max);
    }
}
