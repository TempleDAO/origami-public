pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IEVC } from "contracts/interfaces/external/ethereum-vault-connector/IEthereumVaultConnector.sol";
import {
    IEVKEVault as IEVault,
    IEVKRiskManager as IRiskManager
} from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { IEVKGovernance as IEGovernance } from "contracts/interfaces/external/euler/IEVKEVault.sol";
import { EVCUtil } from "contracts/external/ethereum-vault-connector/utils/EVCUtil.sol";
import "contracts/external/euler-vault-kit/Constants.sol" as EulerConstants;
import { Flags } from "contracts/external/euler-vault-kit/FlagsLib.sol";
import { AmountCap, AmountCapLib } from "contracts/external/euler-vault-kit/AmountCapLib.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOpalAdapterEuler } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterEuler.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterEuler } from "contracts/investments/opal/adapters/OpalAdapterEuler.sol";
import { MockSwapPlugin } from "test/foundry/mocks/common/bundler/plugins/MockSwapPlugin.m.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

interface IEulerFactoryGovernor {
    function pause(address factory) external;
}

contract OpalAdapterEulerTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    error E_AccountLiquidity();
    error E_InsufficientBalance();

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterEuler internal adapterImpl;

    OpalAdapterEuler internal adapter;
    MockSwapPlugin internal mockSwapPlugin;

    address internal manager;

    address internal constant EULER_VAULT_FACTORY = 0x29a56a1b8214D9Cf7c5561811750D5cBDb45CC8e;
    IEulerFactoryGovernor internal constant EULER_FACTORY_GOVERNOR =
        IEulerFactoryGovernor(0x2F13256E04022d6356d8CE8C53C7364e13DC1f3d);

    IEVC internal constant EULER_EVC = IEVC(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383);
    address public user = 0xFB0C51cD7725C3b5D6a57ce17c9591d9cD1B9452;

    IERC20 internal constant SUSDE_VAULT = IERC20(0x56B829e465170c3aCcAd33a3E0512b239b202242);
    IERC20 internal constant SUSDE = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 internal constant PT_SUSDE_NOV_VAULT = IERC20(0x9D4265a05a6A0C7F3EcB179F4BA5C3197CBb8F16);
    IERC20 internal constant PT_SUSDE_NOV = IERC20(0xe6A934089BBEe34F832060CE98848359883749B3);

    IERC20 internal constant USDC_VAULT = IERC20(0x9bD52F2805c6aF014132874124686e7b248c2Cbb);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.93e18; // 93%

    uint32 internal constant OP_NONE_DISABLED = 0;
    uint32 internal constant OP_EXIT_DISABLED =
        EulerConstants.OP_WITHDRAW | EulerConstants.OP_REDEEM | EulerConstants.OP_REPAY;
    uint32 internal constant OP_JOIN_DISABLED = EulerConstants.OP_DEPOSIT | EulerConstants.OP_BORROW;
    uint32 internal constant OP_ALL_DISABLED = OP_JOIN_DISABLED | OP_EXIT_DISABLED;

    function setUp() public {
        fork("mainnet", 23_609_410);

        manager = address(new OrigamiBundler());
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new OpalAdapterEuler("EulerV2.1", address(EULER_EVC));
        mockSwapPlugin = new MockSwapPlugin(manager);
        vm.label(address(adapterImpl), "EULERV2.1 [IMPL]");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(address(PT_SUSDE_NOV_VAULT), address(USDC_VAULT));

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );
        vm.label(address(adapter), "AdapterEuler [PT-sUSDe-Nov]/[USDC]");
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, MAX_LOAN_UR_ON_JOIN));

        vm.stopPrank();
    }

    function checkExpectedBs(uint256 collateralAmount, uint256 debtAmount) internal view {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        expectArr(totalAssets, mkArray(collateralAmount));
        expectArr(totalLiabilities, mkArray(debtAmount));
    }

    function supply(IERC20 token, uint256 amount) internal {
        deal(address(token), address(adapter), amount);
        vm.startPrank(manager);
        adapter.supplyCollateral(amount, 1);
        vm.stopPrank();
    }

    function updateMaxLoanTokenUtilizationRatio(uint256 newRatio) internal {
        vm.startPrank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(newRatio);
        vm.stopPrank();
    }

    function doJoin(uint256 collateralAmt, uint256 borrowAmt) internal {
        vm.startPrank(manager);
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        vm.stopPrank();
    }

    function updateVaultParameters(IEVault vault, uint32 hookedOps, uint16 supplyCap, uint16 borrowCap) internal {
        address governor = vault.governorAdmin();
        vm.startPrank(governor);
        vault.setHookConfig(address(0), hookedOps);

        // Update caps (0 = unlimited, per AmountCap rules)
        // Disabling operational flags superceeds caps
        vault.setCaps(supplyCap, borrowCap);
    }
}

contract OpalAdapterEulerTestAdmin is OpalAdapterEulerTestBase {
    function test_initialization_euler_adapter() public view {
        assertEq(adapter.owner(), origamiMultisig);
        assertEq(adapter.implTypeAndVersion(), "EulerV2.1");
        assertEq(adapter.manager(), manager);
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.description(), "[PT-sUSDe-Nov]/[USDC]");
        assertEq(address(adapter.EVC()), address(EULER_EVC));
        assertEq(address(adapter.eulerEVC()), address(EULER_EVC));
        assertEq(adapter.collateralToken(), address(PT_SUSDE_NOV));
        assertEq(address(adapter.collateralVault()), address(PT_SUSDE_NOV_VAULT));
        assertEq(adapter.loanToken(), address(USDC));
        assertEq(address(adapter.borrowVault()), address(USDC_VAULT));

        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        expectArr(assetTokens, address(PT_SUSDE_NOV));
        expectArr(liabilityTokens, address(USDC));

        assertEq(adapter.maxSafeLtv(), 0.82e18);
        assertEq(adapter.liquidationLtv(), 0.86e18);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), MAX_LOAN_UR_ON_JOIN);

        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        expectArr(assetGroupIds, 0x0000000000000000000000009d4265a05a6a0c7f3ecb179f4ba5c3197cbb8f16);
        expectArr(liabilityGroupIds, 0x0000000000000000000000009bd52f2805c6af014132874124686e7b248c2cbb);

        {
            (
                OpalAdapterEuler.AssetSupplyMetrics memory supplyMetrics,
                OpalAdapterEuler.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertFalse(supplyMetrics.supplyingDisabled);
            assertEq(supplyMetrics.eulerSupplyCap, 10_000_000e18);
            assertEq(supplyMetrics.alreadySupplied, 449_430.371001588041470963e18);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.eulerBorrowCap, 1.08e14);
            assertEq(borrowMetrics.joinBorrowCap, 102_635_764.434751e6);
            assertEq(borrowMetrics.alreadyBorrowed, 9.1667065018571e13);
            assertEq(borrowMetrics.availableSupply, 1.8693972008043e13);
        }

        {
            (
                OpalAdapterEuler.AssetWithdrawMetrics memory withdrawMetrics,
                OpalAdapterEuler.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertFalse(withdrawMetrics.withdrawingDisabled);
            assertEq(withdrawMetrics.availableSupply, 449_430.371001588041470963e18);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.totalDebt, 9.1667065018571e13);
        }

        assertTrue(EULER_EVC.isCollateralEnabled(address(adapter), address(PT_SUSDE_NOV_VAULT)));
        assertFalse(EULER_EVC.isCollateralEnabled(address(adapter), address(USDC_VAULT)));
        assertFalse(EULER_EVC.isControllerEnabled(address(adapter), address(PT_SUSDE_NOV_VAULT)));
        assertTrue(EULER_EVC.isControllerEnabled(address(adapter), address(USDC_VAULT)));

        bytes19 prefix = EULER_EVC.getAddressPrefix(address(adapter));
        assertTrue(EULER_EVC.isLockdownMode(prefix));
        assertTrue(EULER_EVC.isPermitDisabledMode(prefix));

        assertEq(USDC.allowance(address(adapter), address(USDC_VAULT)), type(uint256).max);
        assertEq(PT_SUSDE_NOV.allowance(address(adapter), address(PT_SUSDE_NOV_VAULT)), type(uint256).max);

        checkExpectedBs(0, 0);

        // Adapter supply is 0, so `maxSafeLtv` returns 0
        adapter.validateLtvInRange(0, adapter.maxSafeLtv()); // no-op
        adapter.validateLtvInRange(0, 0.9e18);

        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
        expectArr(assetAmounts, 9_550_569.628998411958529037e18);
        expectArr(liabilityAmounts, 10_968_699.41618e6);

        (assetAmounts, liabilityAmounts) = adapter.maxExit();
        expectArr(assetAmounts, 449_430.371001588041470963e18);
        expectArr(liabilityAmounts, 91_667_065.018571e6);
    }

    function test_initialize_fail_collateral_loan_tokens_check() public {
        bytes memory immutableArgs = abi.encodePacked(
            address(PT_SUSDE_NOV),
            address(PT_SUSDE_NOV_VAULT),
            address(PT_SUSDE_NOV), // wrong loan token, same as collateral token
            address(USDC_VAULT)
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 0.9e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(PT_SUSDE_NOV)));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_maxURTooHigh() public {
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(address(PT_SUSDE_NOV_VAULT), address(USDC_VAULT));

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 1e18 + 1);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_badCollateralToken() public {
        bytes memory immutableArgs = abi.encodePacked(
            address(SUSDE), // wrong collateral token
            address(PT_SUSDE_NOV_VAULT),
            address(USDC),
            address(USDC_VAULT)
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 0.9e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(SUSDE)));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_badLoanToken() public {
        bytes memory immutableArgs = abi.encodePacked(
            address(PT_SUSDE_NOV),
            address(PT_SUSDE_NOV_VAULT),
            address(SUSDE), // wrong loan token
            address(USDC_VAULT)
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 0.9e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(SUSDE)));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_missingBorrowVault() public {
        bytes memory immutableArgs = abi.encodePacked(
            address(PT_SUSDE_NOV),
            address(PT_SUSDE_NOV_VAULT),
            address(USDC)
            // borrow vault missing
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert("call to non-contract address 0x0000000000000000000000000000000000000000");
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_zero_address_collateral() public {
        bytes memory immutableArgs =
            abi.encodePacked(address(0), address(PT_SUSDE_NOV_VAULT), address(USDC), address(USDC_VAULT));

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 0.9e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        adapter.initialize(initArgs);
    }

    function test_initializa_fail_zero_address_loanToken() public {
        bytes memory immutableArgs =
            abi.encodePacked(address(PT_SUSDE_NOV), address(PT_SUSDE_NOV_VAULT), address(0), address(USDC_VAULT));

        vm.startPrank(address(manager));
        adapter = OpalAdapterEuler(
            adapterFactory.create(address(adapterImpl), address(manager), "[PT-sUSDe-Nov]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, 0.9e18);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        adapter.initialize(initArgs);
    }

    function test_encodeImmutableArgs_fail_sameAsset() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(SUSDE)));
        adapter.encodeImmutableArgs(address(SUSDE_VAULT), address(SUSDE_VAULT));
    }

    function test_setMaxLoanUtilizationRatioOnJoin_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18 + 1);
    }

    function test_setMaxLoanUtilizationRatioOnJoin_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterEuler.MaxLoanUtilizationRatioOnJoinSet(1e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), 1e18);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IOpalAdapterEuler).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOpalAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(adapter.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OpalAdapterEulerTestAccess is OpalAdapterEulerTestBase {
    function test_access_setMaxLoanUtilizationRatioOnJoin() public {
        expectElevatedAccess();
        adapter.setMaxLoanUtilizationRatioOnJoin(0);
    }

    // Only Manager (aka bundler):

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

    function test_access_supplyCollateral() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.supplyCollateral(0, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.supplyCollateral(0, 0);
    }

    function test_access_withdrawCollateral() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.withdrawCollateral(0, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.withdrawCollateral(0, alice);
    }

    function test_access_borrow() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.borrow(0, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.borrow(0, alice);
    }

    function test_access_repay() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.repay(0, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.repay(0, 0);
    }

    function test_access_withDeferredEulerChecks_bundler_check() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.withDeferredEulerChecks(bytes(""));

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.withDeferredEulerChecks(bytes(""));
    }

    function test_access_withDeferredEulerChecks_evc_check() public {
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        MaliciousCallerViaEVC maliciousContract = new MaliciousCallerViaEVC(address(EULER_EVC), address(adapter));

        vm.expectRevert(
            abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, address(maliciousContract))
        );
        maliciousContract.callOnlyElevatedAccessFunctionFromOpalAdapterEuler_withDeferredEulerChecks();
    }
}

contract MaliciousCallerViaEVC is EVCUtil {
    OpalAdapterEuler public immutable eulerAdapter;

    constructor(address _evc, address _eulerAdapter) EVCUtil(_evc) {
        eulerAdapter = OpalAdapterEuler(_eulerAdapter);
    }

    function callOnlyElevatedAccessFunctionFromOpalAdapterEuler_withDeferredEulerChecks() public callThroughEVC {
        bytes memory data = abi.encode(bytes(""));
        eulerAdapter.withDeferredEulerChecks(data);
    }
}

contract OpalAdapterEulerTestJoinExit is OpalAdapterEulerTestBase {
    function test_join_fail_wrongLength() public {
        vm.startPrank(manager);

        // 0 length
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(new uint256[](0), mkArray(123e18), alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18), new uint256[](0), alice);

        // length > 1
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18, 123e18), mkArray(123e18), alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18), mkArray(123e18, 123e18), alice);
    }

    function test_join_fail_noAllowance() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: insufficient allowance");
        adapter.join(mkArray(123e18), mkArray(0), alice);
    }

    function test_join_fail_noBalance() public {
        vm.startPrank(manager);
        PT_SUSDE_NOV.approve(address(adapter), 123e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        adapter.join(mkArray(123e18), mkArray(0), alice);
    }

    function test_join_success() public {
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 9_550_569.628998411958529037e18);
        expectArr(liabilities, 10_968_699.41618e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 449_430.371001588041470963e18);
        expectArr(liabilities, 91_667_065.018571e6);

        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        vm.startPrank(manager);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt, borrowAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.818592301641682106e18);
        assertEq(adapter.healthFactor(), 1.05058403099476381e18);
        adapter.validateLtvInRange(0, adapter.maxSafeLtv());

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 9_550_446.628998411958529037e18);
        expectArr(liabilities, 10_968_599.41618e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 449_553.371001588041470963e18);
        expectArr(liabilities, 91_667_165.018571e6);
    }

    function test_join_someCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 420e18;
        uint256 borrowAmt = 0;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        vm.startPrank(manager);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(0));
        adapter.join(mkArray(collateralAmt), mkArray(0), alice);

        checkExpectedBs(collateralAmt, borrowAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, 0.93e18);
    }

    function test_join_zeroCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 0;
        uint256 borrowAmt = 0;

        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt, borrowAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, 0.93e18);
    }

    function test_join_zeroCollateral_someBorrow() public {
        vm.startPrank(manager);

        // Do an initial join first
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        {
            deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
            PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
            vm.expectEmit(address(adapter));
            emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
            adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        }

        collateralAmt = 0;
        borrowAmt = 1e18;
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overSafeLtv_simple() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100.2e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        vm.expectRevert(abi.encodeWithSelector(E_AccountLiquidity.selector));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overSafeLtv_skipForward() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100.17e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        IOpalAdapterEuler.EulerPositionDetails memory details = adapter.positionDetails();
        assertEq(details.supplied, 123e18);
        assertEq(details.borrowed, 100.17e6);
        assertEq(details.collateralValueInUnitOfAcct, 122.156029075106903673e18);
        assertEq(details.liabilityValueInUnitOfAcct, 100.1659781745e18);
        assertEq(details.liquidationLtv, 0.86e18);
        assertEq(details.maxSafeLtv, 0.82e18);
        assertEq(details.currentLtv, 0.819983908554472965e18);
        assertEq(details.healthFactor, 1.048801069177162634e18);

        // Show joining again with 1/10th of that same ratio works ok
        collateralAmt /= 10;
        borrowAmt /= 10;
        uint256 snapId = vm.snapshot();
        {
            deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
            PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
            adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        }
        vm.revertToStateAndDelete(snapId);

        // Skip forward 30 days
        // Tweak the oracle data such that the Use the same oracle data later - avoid the staleness check
        skip(30 days);
        {
            bytes4 latestRoundDataSelector = bytes4(keccak256("latestRoundData()"));
            vm.mockCall(
                0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58,
                latestRoundDataSelector,
                abi.encode(1, 99_958_757, 1_760_783_483 + 30 days, 1_760_783_483 + 30 days, 1)
            );
            vm.mockCall(
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6,
                latestRoundDataSelector,
                abi.encode(
                    55_340_232_221_128_655_400,
                    99_995_985,
                    1_760_842_900 + 30 days,
                    1_760_842_919 + 30 days,
                    55_340_232_221_128_655_400
                )
            );
        }

        details = adapter.positionDetails();
        assertEq(details.supplied, 123e18);
        assertEq(details.borrowed, 100.82652e6);
        assertEq(details.collateralValueInUnitOfAcct, 122.770095207830953289e18);
        assertEq(details.liabilityValueInUnitOfAcct, 100.822471815222e18);
        assertEq(details.liquidationLtv, 0.86e18);
        assertEq(details.maxSafeLtv, 0.82e18);
        assertEq(details.currentLtv, 0.821229890263952383e18);
        assertEq(details.healthFactor, 1.047209813227312603e18);

        // Can't borrow the same ratio now because the debt has increased.
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        vm.expectRevert(abi.encodeWithSelector(E_AccountLiquidity.selector));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_withBorrow() public {
        vm.startPrank(origamiMultisig);
        uint256 currentUR = adapter.currentLoanTokenUtilizationRatio();
        assertEq(currentUR, 0.830610761626543299e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(currentUR);

        vm.startPrank(manager);
        uint256 collateralAmt = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.830611667743436491e18, 0, currentUR
            )
        );
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_zeroBorrow() public {
        vm.startPrank(origamiMultisig);
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.830610761626543299e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(0.7e18);

        vm.startPrank(manager);
        uint256 collateralAmt = 1e18;
        uint256 borrowAmt = 0;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        checkExpectedBs(collateralAmt, borrowAmt);
    }

    function test_join_fail_notEnoughCollateral() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;

        // max borrow
        //  aave USDC/USD oracle price: 0.99995985e8
        //  position.collateralValueInUnitOfAcct: 122.156029075106903673e18
        //  max borrow LTV (maxSafeLTV) = 0.82e18
        //  max USDC to borrow: (122.156029075106903673e18 * 0.82e18 / 1e18) / 0.99995985e8 / 1e4 = 100.171965e6
        uint256 maxBorrowAmt = (uint256(122.156029075106903673e18) * 0.82e18 / 1e18) / 0.99995985e8 / 1e4;
        assertEq(maxBorrowAmt, 100.171965e6);
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);

        vm.expectRevert(abi.encodeWithSelector(E_AccountLiquidity.selector));
        adapter.join(mkArray(collateralAmt), mkArray(maxBorrowAmt + 1), alice);

        // one less is ok
        adapter.join(mkArray(collateralAmt), mkArray(maxBorrowAmt), alice);
        assertEq(adapter.currentLtv(), 0.819999993893200224e18); // now LTV is tiny bit under the max borrow LTV
    }

    function test_exit_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18, 420e18), mkArray(123e18), alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18), mkArray(123e18, 420e18), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(new uint256[](0), mkArray(123e18), alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18), new uint256[](0), alice);
    }

    function test_exit_fail_notEnough() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        adapter.exit(mkArray(1), mkArray(123e18), alice);
    }

    function test_exit_success() public {
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 9_550_569.628998411958529037e18);
        expectArr(liabilities, 10_968_699.41618e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 449_430.371001588041470963e18);
        expectArr(liabilities, 91_667_065.018571e6);

        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e6;
        uint256 withdrawAmt = 10e18;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.596992845825584269e18);
        assertEq(adapter.healthFactor(), 1.440553276330643253e18);
        adapter.validateLtvInRange(0, 0.93e18);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 9_550_456.628998411958529037e18);
        expectArr(liabilities, 10_968_632.41618e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 449_543.371001588041470963e18);
        expectArr(liabilities, 91_667_132.018571e6);
    }

    function test_exit_zeroRepay_someWithdrawal() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 0;
        uint256 withdrawAmt = 20e18;
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.251717132754817248e18);
        assertEq(adapter.healthFactor(), 3.416533434129313198e18);
        adapter.validateLtvInRange(0, 0.93e18);
    }

    function test_exit_zeroRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        assertEq(adapter.currentLtv(), 0.239730602623635474e18);
        assertEq(adapter.healthFactor(), 3.587360105835778863e18);

        uint256 repayAmt = 0;
        uint256 withdrawAmt = 0;
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.239730602623635474e18);
        assertEq(adapter.healthFactor(), 3.587360105835778863e18);
        adapter.validateLtvInRange(0, 0.93e18);
    }

    function test_exit_someRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e6;
        uint256 withdrawAmt = 0;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);
    }

    function test_exit_repayTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 101e6;
        uint256 withdrawAmt = collateralAmt;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(0, 0);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(USDC.balanceOf(address(adapter)), 1e6);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, 0.93e18);
    }

    function test_exit_maxWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 100e6;
        uint256 withdrawAmt = type(uint256).max;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);

        // Note the event amount shows 'max'. Not realistic that the manager would send
        // through max anyway
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(0, 0);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), collateralAmt);
        assertEq(PT_SUSDE_NOV.balanceOf(manager), 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_exit_withdrawTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        deal(address(PT_SUSDE_NOV), address(manager), collateralAmt);
        PT_SUSDE_NOV.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 100e6;
        uint256 withdrawAmt = 500e18;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);

        vm.expectRevert(abi.encodeWithSelector(E_InsufficientBalance.selector));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);
    }
}

contract OpalAdapterEulerTestBundlerActions is OpalAdapterEulerTestBase {
    function test_supplyCollateral_zeroAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        adapter.supplyCollateral(collateralAmt, 0);

        // No-op if under the min
        adapter.supplyCollateral(collateralAmt, 1);
        checkExpectedBs(collateralAmt, 0);
    }

    function test_supplyCollateral_specifiedAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0), collateralAmt);
        checkExpectedBs(collateralAmt, 0);
    }

    function test_supplyCollateral_maxOverMinAmount() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt);
        assertEq(adapter.supplyCollateral(type(uint256).max, collateralAmt), collateralAmt);
    }

    function test_supplyCollateral_maxUnderMinAmount() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt);
        assertEq(adapter.supplyCollateral(type(uint256).max, collateralAmt + 1), 0);

        // No op
        checkExpectedBs(0, 0);
    }

    function test_withdrawCollateral_zeroAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 0;
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        adapter.withdrawCollateral(collateralAmt, alice);
    }

    function test_withdrawCollateral_notEnough() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        vm.expectRevert(abi.encodeWithSelector(E_InsufficientBalance.selector));
        adapter.withdrawCollateral(collateralAmt, alice);
    }

    function test_withdrawCollateral_specifiedAmt() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        uint256 withdrawAmt = 123e18;
        assertEq(adapter.withdrawCollateral(withdrawAmt, alice), withdrawAmt);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), withdrawAmt);
        checkExpectedBs(supplyAmt - withdrawAmt, 0);
    }

    function test_withdrawCollateral_max() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        assertEq(adapter.withdrawCollateral(type(uint256).max, alice), supplyAmt);
        assertEq(PT_SUSDE_NOV.balanceOf(alice), supplyAmt);
        checkExpectedBs(0, 0);
    }

    function test_borrow_notEnoughCollateral() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        uint256 borrowAmt = 1076e6;
        vm.expectRevert(abi.encodeWithSelector(E_AccountLiquidity.selector));
        adapter.borrow(borrowAmt, alice);
    }

    function test_borrow_success() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        uint256 borrowAmt = 780e6;
        adapter.borrow(borrowAmt, alice);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.785357454195029812e18);
        assertEq(adapter.healthFactor(), 1.095042767349138848e18);
    }

    function test_borrow_zeroAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        adapter.borrow(0, alice);
    }

    function test_repay_tooManyAssets() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        assertEq(adapter.repay(borrowAmt + 1e6, 0), borrowAmt);
        assertEq(USDC.balanceOf(address(adapter)), 1e6); // left over in the contract
        checkExpectedBs(supplyAmt, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_max_overMinAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // Pays off as much as possible
        assertEq(adapter.repay(type(uint256).max, borrowAmt + 1e6), borrowAmt);
        assertEq(USDC.balanceOf(address(adapter)), 1e6);
        checkExpectedBs(supplyAmt, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_max_underMinAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // Under threshold
        assertEq(adapter.repay(type(uint256).max, borrowAmt + 1e6 + 1), 0);
        assertEq(USDC.balanceOf(address(adapter)), borrowAmt + 1e6);
        checkExpectedBs(supplyAmt, borrowAmt);
        assertEq(adapter.currentLtv(), 0.755151398264451743e18);
        assertEq(adapter.healthFactor(), 1.138844478043104401e18);
    }

    function test_repay_exact() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(PT_SUSDE_NOV), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        assertEq(adapter.repay(borrowAmt, borrowAmt), borrowAmt);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        checkExpectedBs(supplyAmt, 0);
        // Zero because no outstanding gwei after repay
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_withDeferredEulerChecks_withdrawThenRepay() public {
        uint256 collateralAmt = 123e18;
        uint256 debtAmt = 100e6;
        doJoin(collateralAmt, debtAmt);
        OpalAdapterEuler.EulerPositionDetails memory positionDetails = adapter.positionDetails();
        assertEq(positionDetails.supplied, collateralAmt);
        assertEq(positionDetails.borrowed, debtAmt);
        assertEq(positionDetails.collateralValueInUnitOfAcct, 122.156029075106903673e18);
        assertEq(positionDetails.liabilityValueInUnitOfAcct, 99.995985e18);
        assertEq(positionDetails.liquidationLtv, 0.86e18);
        assertEq(positionDetails.maxSafeLtv, 0.82e18);
        assertEq(positionDetails.currentLtv, 0.818592301641682106e18);
        assertEq(positionDetails.healthFactor, 1.05058403099476381e18);

        // Deal the mock swap plugin with some USDC
        deal(address(USDC), address(mockSwapPlugin), debtAmt);

        Call[] memory innerBundle = new Call[](3);
        innerBundle[0] = createCall(
            adapter,
            abi.encodeWithSelector(
                IOpalAdapterEuler.withdrawCollateral.selector, collateralAmt, address(mockSwapPlugin)
            )
        );
        innerBundle[1] = createCall(
            mockSwapPlugin,
            abi.encodeWithSelector(
                MockSwapPlugin.swap.selector,
                address(PT_SUSDE_NOV),
                collateralAmt,
                address(USDC),
                debtAmt,
                address(adapter)
            )
        );
        innerBundle[2] = createCall(adapter, abi.encodeWithSelector(IOpalAdapterEuler.repay.selector, debtAmt, debtAmt));
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = new Call[](1);
        outerBundle[0] = createCall(
            adapter,
            abi.encodeWithSelector(IOpalAdapterEuler.withDeferredEulerChecks.selector, encodedInnerBundle),
            keccak256(encodedInnerBundle)
        );
        vm.startPrank(origamiMultisig);
        IOrigamiBundler(manager).multicall(outerBundle);

        positionDetails = adapter.positionDetails();
        assertEq(positionDetails.supplied, 0);
        assertEq(positionDetails.borrowed, 0);
        assertEq(positionDetails.collateralValueInUnitOfAcct, 0);
        assertEq(positionDetails.liabilityValueInUnitOfAcct, 0);
        assertEq(positionDetails.liquidationLtv, 0.86e18);
        assertEq(positionDetails.maxSafeLtv, 0.82e18);
        assertEq(positionDetails.currentLtv, 0);
        assertEq(positionDetails.healthFactor, type(uint256).max);
    }

    function test_validateLtvInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLtvInRange(0.82e18, 0.1e18);
    }

    function test_validateLtvInRange() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt * 2);
        adapter.supplyCollateral(collateralAmt, 0);

        uint256 borrowAmt = 100e6;
        adapter.borrow(borrowAmt, alice);
        assertEq(adapter.currentLtv(), 0.818592301641682106e18);

        // no-op
        adapter.validateLtvInRange(0.81e18, 0.82e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.818592301641682106e18, 0.8e18, 0.81e18)
        );
        adapter.validateLtvInRange(0.8e18, 0.81e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.818592301641682106e18, 0.819e18, 0.8199e18)
        );
        adapter.validateLtvInRange(0.819e18, 0.8199e18);

        // Bound by the max safe ltv within euler
        // `maxLtv` get assigned this value
        uint256 safeLtv = 7500;
        vm.mockCall(
            address(adapter.borrowVault()),
            abi.encodeWithSelector(IEGovernance.LTVBorrow.selector, address(adapter.collateralVault())),
            abi.encode(safeLtv)
        );
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.818592301641682106e18, 0.1e18, 0.75e18)
        );
        adapter.validateLtvInRange(0.1e18, 0.85e18);
    }

    function test_validateLoanUtilizationRatioInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLoanUtilizationRatioInRange(0.82e18, 0.1e18);
    }

    function test_validateLoanUtilizationRatioInRange_rangeChecks() public {
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.830610761626543299e18);

        // no-op
        adapter.validateLoanUtilizationRatioInRange(0.83e18, 0.95e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.830610761626543299e18, 0.81e18, 0.82e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.81e18, 0.82e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.830610761626543299e18, 0.923e18, 0.94e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.923e18, 0.94e18);
    }
}

contract OpalAdapterEulerTestMaxJoinExit is OpalAdapterEulerTestBase {
    using AmountCapLib for AmountCap;

    function expectMaxJoin(uint256 collateralAmt, uint256 debtAmt) internal view {
        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
        expectArr(assetAmounts, collateralAmt);
        expectArr(liabilityAmounts, debtAmt);
    }

    function expectMaxExit(uint256 collateralAmt, uint256 debtAmt) internal view {
        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxExit();
        expectArr(assetAmounts, collateralAmt);
        expectArr(liabilityAmounts, debtAmt);
    }

    function test_maxJoin_default() public {
        assertFalse(adapter.areAnyVaultOperationsDisabled(adapter.collateralVault(), OP_ALL_DISABLED));
        assertFalse(adapter.areAnyVaultOperationsDisabled(adapter.borrowVault(), OP_ALL_DISABLED));

        expectMaxJoin(9_550_569.628998411958529037e18, 10_968_699.41618e6);
        doJoin(123e18, 100e6);
        expectMaxJoin(9_550_446.628998411958529037e18, 10_968_599.41618e6);
        skip(1 days);
        expectMaxJoin(9_550_446.628998411958529037e18, 10_967_201.992123e6);
    }

    function test_maxJoin_zeroFromFlags_asset() public {
        doJoin(123e18, 100e6);
        IEVault borrowVault = adapter.borrowVault();
        IEVault collateralVault = adapter.collateralVault();
        // Only borrow vault parameters updated
        updateVaultParameters(borrowVault, OP_ALL_DISABLED, 0, 0);
        // Expect collateral vault to still allow deposit
        expectMaxJoin(9_550_446.628998411958529037e18, 0);
        // OP_DEPOSIT and OP_BORROW operations disabled on borrow vault
        assertEq(borrowVault.maxWithdraw(address(adapter)), 0);
        assertEq(borrowVault.maxDeposit(address(adapter)), 0);
        // Enable borrowing (repay still disabled) and set cap to 10_000_000e6.
        updateVaultParameters(borrowVault, EulerConstants.OP_REPAY, 0, 0);
        expectMaxJoin(9_550_446.628998411958529037e18, 10_968_599.41618e6);

        // Update collateral vault parameters
        updateVaultParameters(collateralVault, OP_ALL_DISABLED, 0, 0);
        // Expect no deposits
        expectMaxJoin(0, 10_968_599.41618e6);
        assertEq(collateralVault.maxDeposit(address(adapter)), 0);
        assertEq(collateralVault.maxRedeem(address(adapter)), 0);
        updateVaultParameters(collateralVault, OP_EXIT_DISABLED, 0, 0);
        expectMaxJoin(5_192_296_858_085_274.257528908287749132e18, 10_968_599.41618e6);
        assertEq(collateralVault.maxDeposit(address(adapter)), 5_192_296_858_085_274.257528908287749132e18);
    }

    function test_maxJoin_supplyCaps_asset() public {
        doJoin(123e18, 100e6);
        IEVault collateralVault = adapter.collateralVault();
        // 8_590_000 supply cap
        updateVaultParameters(collateralVault, OP_EXIT_DISABLED, uint16(55_000), 0);
        // Subtract collateral cash from supply cap
        uint256 availableToSupply = AmountCap.wrap(uint16(55_000)).resolve() - adapter.collateralVault().cash();
        expectMaxJoin(availableToSupply, 10_968_599.41618e6);
        // unlimited
        updateVaultParameters(collateralVault, OP_EXIT_DISABLED, 0, 0);
        // Even after supply cap is set to 0 (for max),
        // vault maxDeposit limits value to cash remaining space and total shares remaining space
        // https://github.com/euler-xyz/euler-vault-kit/blob/master/src/EVault/modules/Vault.sol#L259
        expectMaxJoin(5_192_296_858_085_274.257528908287749132e18, 10_968_599.41618e6);

        // 77100000 (under current utilized)
        updateVaultParameters(collateralVault, OP_EXIT_DISABLED, uint16(49_351), 0);
        (uint16 supplyCap,) = collateralVault.caps();
        assertEq(AmountCap.wrap(uint16(supplyCap)).resolve(), 77_100_000);
        expectMaxJoin(0, 10_968_599.41618e6);
    }

    function test_maxJoin_borrowCaps_liability() public {
        doJoin(123e18, 100e6);
        IEVault borrowVault = adapter.borrowVault();
        // unlimited cap - uses available not yet borrowed
        updateVaultParameters(borrowVault, OP_EXIT_DISABLED, 0, 0);
        (, uint16 borrowCap) = borrowVault.caps();
        uint256 cap = AmountCap.wrap(borrowCap).resolve();
        assertEq(type(uint256).max, cap);
        expectMaxJoin(9_550_446.628998411958529037e18, 10_968_599.41618e6);
        // 820 milli cap and 91.6 milli utilized - use amount left below cap (and available to borrow)
        // 50381 - 78700000000000 (78 milli)
        updateVaultParameters(borrowVault, OP_EXIT_DISABLED, 0, uint16(52_494));
        expectMaxJoin(9_550_446.628998411958529037e18, 10_968_599.41618e6);

        // 77 (under current utilized)
        updateVaultParameters(borrowVault, OP_EXIT_DISABLED, 0, uint16(49_351));
        (, borrowCap) = borrowVault.caps();
        cap = AmountCap.wrap(borrowCap).resolve();
        assertEq(cap, 77.1e6);
        expectMaxJoin(9_550_446.628998411958529037e18, 0);
    }

    function test_maxExit_default() public {
        expectMaxExit(449_430.371001588041470963e18, 91_667_065.018571e6);
        doJoin(123e18, 100e6);
        expectMaxExit(449_553.371001588041470963e18, 91_667_165.018571e6);
        skip(1 days);
        expectMaxExit(449_553.371001588041470963e18, 91_687_128.219382e6);
    }
}

contract OpalAdapterEulerTestViews is OpalAdapterEulerTestBase {
    function supply(uint256 amount) internal {
        deal(address(PT_SUSDE_NOV), address(adapter), amount);
        vm.startPrank(manager);
        adapter.supplyCollateral(amount, 0);
        vm.stopPrank();
    }

    function test_areAnyVaultOperationsDisabled() public {
        IEVault vault = adapter.borrowVault();
        updateVaultParameters(vault, EulerConstants.OP_DEPOSIT, 0, 0);
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT));
        assertFalse(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_WITHDRAW));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_WITHDRAW));

        updateVaultParameters(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_WITHDRAW, 0, 0);
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_WITHDRAW));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_WITHDRAW));

        updateVaultParameters(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_REPAY, 0, 0);
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT));
        assertFalse(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_WITHDRAW));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_REPAY));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_REPAY));
        assertTrue(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_DEPOSIT | EulerConstants.OP_WITHDRAW));
        assertFalse(adapter.areAnyVaultOperationsDisabled(vault, EulerConstants.OP_REDEEM | EulerConstants.OP_WITHDRAW));
    }

    function test_positionDetails() public {
        uint256 collateralAmount = 100e18;
        supply(collateralAmount);

        uint256 borrowAmt = 78e6;
        vm.prank(manager);
        adapter.borrow(borrowAmt, alice);

        IOpalAdapterEuler.EulerPositionDetails memory details = adapter.positionDetails();
        assertEq(details.supplied, collateralAmount);
        assertEq(details.borrowed, borrowAmt);
        assertEq(details.collateralValueInUnitOfAcct, 99.313844776509677782e18);
        assertEq(details.liabilityValueInUnitOfAcct, 77.9968683e18);
        assertEq(details.liquidationLtv, 0.86e18);
        assertEq(details.maxSafeLtv, 0.82e18);
        assertEq(details.currentLtv, 0.785357454195029812e18);
        assertEq(details.healthFactor, 1.095042767349138848e18);

        // liabilityValueInUnitOfAcct value is > 0 and collateralValueInUnitOfAcct is 0
        vm.mockCall(
            address(adapter.borrowVault()),
            abi.encodeWithSelector(IRiskManager.accountLiquidity.selector, address(adapter), true),
            abi.encode(uint256(0), uint256(1e6))
        );
        details = adapter.positionDetails();
        assertEq(details.collateralValueInUnitOfAcct, 0);
        assertEq(details.liabilityValueInUnitOfAcct, 1e6);
        assertEq(details.currentLtv, type(uint256).max);
        assertEq(details.healthFactor, 0);

        // liabilityValueInUnitOfAcct value is 0 and collateralValueInUnitOfAcct is > 0
        vm.mockCall(
            address(adapter.borrowVault()),
            abi.encodeWithSelector(IRiskManager.accountLiquidity.selector, address(adapter), true),
            abi.encode(uint256(1e18), uint256(0))
        );
        details = adapter.positionDetails();
        assertEq(details.collateralValueInUnitOfAcct, 1.162790697674418604e18);
        assertEq(details.liabilityValueInUnitOfAcct, 0);
        assertEq(details.currentLtv, 0);
        assertEq(details.healthFactor, type(uint256).max);
    }

    function test_currentLtv_noDebt() public {
        uint256 amount = 500e18;
        supply(PT_SUSDE_NOV, amount);
        assertEq(adapter.currentLtv(), 0);
    }

    function test_currentLtv_noCollateral() public {
        vm.startPrank(origamiMultisig);
        vm.mockCall(
            address(adapter.borrowVault()),
            abi.encodeWithSelector(IRiskManager.accountLiquidity.selector, address(adapter), true),
            abi.encode(0, 1e18)
        );
        assertEq(adapter.currentLtv(), type(uint256).max);
    }

    function test_currentLtv_withDebt() public {
        doJoin(420e18, 100e6);

        assertEq(adapter.currentLtv(), 0.239730602623635474e18);
        assertEq(adapter.maxSafeLtv(), 0.82e18);
        assertEq(adapter.liquidationLtv(), 0.86e18);
    }

    function checkSupplyMetrics(bool expectedDisabled, uint256 expectedCap, uint256 expectedSupplied) private view {
        (OpalAdapterEuler.AssetSupplyMetrics memory supplyMetrics,) = adapter.joinMetrics();
        assertEq(supplyMetrics.supplyingDisabled, expectedDisabled);
        assertEq(supplyMetrics.eulerSupplyCap, expectedCap);
        assertEq(supplyMetrics.alreadySupplied, expectedSupplied);
    }

    function test_joinMetrics_supply() public {
        checkSupplyMetrics(false, 10_000_000e18, 449_430.371001588041470963e18);

        doJoin(420e18, 100e6);
        checkSupplyMetrics(false, 10_000_000e18, 449_850.371001588041470963e18);

        // disabled with no cap
        IEVault collateralVault = adapter.collateralVault();
        uint32 OP_ONLY_BORROW = OP_EXIT_DISABLED | EulerConstants.OP_DEPOSIT;
        updateVaultParameters(collateralVault, OP_ONLY_BORROW, 0, 0);
        checkSupplyMetrics(true, type(uint256).max, 449_850.371001588041470963e18);

        // borrow enabled again - no supply cap
        updateVaultParameters(collateralVault, OP_EXIT_DISABLED, 0, 0);
        checkSupplyMetrics(false, type(uint256).max, 449_850.371001588041470963e18);
    }

    function checkBorrowMetrics(
        bool expectedDisabled,
        uint256 expectedCap,
        uint256 alreadyBorrowed,
        uint256 availableSupply,
        uint256 joinBorrowCap
    ) private view {
        (, OpalAdapterEuler.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
        assertEq(borrowMetrics.borrowingDisabled, expectedDisabled);
        assertEq(borrowMetrics.eulerBorrowCap, expectedCap);
        assertEq(borrowMetrics.alreadyBorrowed, alreadyBorrowed);
        assertEq(borrowMetrics.availableSupply, availableSupply);
        assertEq(borrowMetrics.joinBorrowCap, joinBorrowCap);
    }

    function test_joinMetrics_borrow() public {
        checkBorrowMetrics(false, 108_000_000e6, 91_667_065.018571e6, 18_693_972.008043e6, 102_635_764.434751e6);

        doJoin(420e18, 100e6);
        checkBorrowMetrics(false, 108_000_000e6, 91_667_165.018571e6, 18_693_872.008043e6, 102_635_764.434751e6);

        IEVault borrowVault = adapter.borrowVault();
        // disabled no cap
        uint32 OP_ONLY_SUPPLY = OP_EXIT_DISABLED | EulerConstants.OP_BORROW;
        updateVaultParameters(borrowVault, OP_ONLY_SUPPLY, 0, 0);
        checkBorrowMetrics(true, type(uint256).max, 91_667_165.018571e6, 18_693_872.008043e6, 102_635_764.434751e6);

        // no borrow cap
        updateVaultParameters(borrowVault, OP_EXIT_DISABLED, 0, 0);
        checkBorrowMetrics(false, type(uint256).max, 91_667_165.018571e6, 18_693_872.008043e6, 102_635_764.434751e6);

        // No max UR
        updateMaxLoanTokenUtilizationRatio(1e18);
        checkBorrowMetrics(false, type(uint256).max, 91_667_165.018571e6, 18_693_872.008043e6, type(uint256).max);
    }

    function checkWithdrawMetrics(bool expectedDisabled, uint256 availableSupply) private view {
        (OpalAdapterEuler.AssetWithdrawMetrics memory withdrawMetrics,) = adapter.exitMetrics();
        assertEq(withdrawMetrics.withdrawingDisabled, expectedDisabled);
        assertEq(withdrawMetrics.availableSupply, availableSupply);
    }

    function test_exitMetrics_withdraw() public {
        checkWithdrawMetrics(false, 449_430.371001588041470963e18);

        doJoin(420e18, 100e6);
        checkWithdrawMetrics(false, 449_850.371001588041470963e18);

        IEVault collateralVault = adapter.collateralVault();
        // disabled no supply cap
        updateVaultParameters(collateralVault, OP_ALL_DISABLED, 0, 0);
        checkWithdrawMetrics(true, 449_850.371001588041470963e18);

        // no supply cap
        updateVaultParameters(collateralVault, OP_NONE_DISABLED, 0, 0);
        checkWithdrawMetrics(false, 449_850.371001588041470963e18);
    }

    function checkRepayMetrics(bool expectedDisabled, uint256 totalDebt) private view {
        (, OpalAdapterEuler.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
        assertEq(repayMetrics.repayingDisabled, expectedDisabled);
        assertEq(repayMetrics.totalDebt, totalDebt);
    }

    function test_exitMetrics_repay() public {
        checkRepayMetrics(false, 91_667_065.018571e6);

        doJoin(420e18, 100e6);
        checkRepayMetrics(false, 91_667_165.018571e6);

        IEVault borrowVault = adapter.borrowVault();
        // Disable repay no caps
        updateVaultParameters(borrowVault, EulerConstants.OP_REPAY, 0, 0);
        checkRepayMetrics(true, 91_667_165.018571e6);

        // no borrow cap
        updateVaultParameters(borrowVault, EulerConstants.OP_WITHDRAW | EulerConstants.OP_REDEEM, 0, 0);
        checkRepayMetrics(false, 91_667_165.018571e6);
    }
}

interface IReadOnlyProxy {
    function roProxyImplementation() external view returns (address);
}

interface IGenericFactory {
    /// @notice Check if an address is a proxy deployed with this factory
    /// @param proxy Address to check
    /// @return True if the address is a proxy
    function isProxy(address proxy) external view returns (bool);
}

contract CustomHook {
    error CustomError();

    /// @notice The EVault factory contract.
    IGenericFactory public immutable eVaultFactory;

    /// @notice Constructor
    /// @param _eVaultFactory The address of the EVault factory contract which deployed the vaults associated with
    /// this hook target.
    constructor(address _eVaultFactory) {
        eVaultFactory = IGenericFactory(_eVaultFactory);
    }

    /// @notice If given contract is a hook target, it is expected to return the bytes4 magic value that is the selector
    /// of this function
    /// @return The bytes4 magic value (0x87439e04) that is the selector of this function
    function isHookTarget() external view returns (bytes4) {
        if (eVaultFactory.isProxy(msg.sender)) return this.isHookTarget.selector;
        else return 0;
    }

    // Exactly the same as the IEVault for the functions the hook is enabled for.
    function deposit(
        uint256 amount,
        address /*receiver*/
    )
        external
        pure
        returns (uint256)
    {
        if (amount > 1e18) revert CustomError();
        return 0;
    }
}

contract OpalAdapterEulerTestEulerPauseMethods is OpalAdapterEulerTestBase {
    // A rough way of checking if the proxy is paused
    // ...but not bullet proof long term so not using within the contracts.
    function isPaused(address eVaultProxy) internal view returns (bool) {
        (bool success,) = eVaultProxy.staticcall(abi.encodeCall(IReadOnlyProxy.roProxyImplementation, ()));
        return success || eVaultProxy.code.length == 0;
    }

    function test_euler_global_pause() public {
        // initial maxJoin/maxExit
        {
            (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
            expectArr(assetAmounts, 9_550_569.628998411958529037e18);
            expectArr(liabilityAmounts, 10_968_699.41618e6);

            (assetAmounts, liabilityAmounts) = adapter.maxExit();
            expectArr(assetAmounts, 449_430.371001588041470963e18);
            expectArr(liabilityAmounts, 91_667_065.018571e6);
        }

        // one of the EOAs with the pause role
        assertFalse(isPaused(address(PT_SUSDE_NOV_VAULT)));
        assertFalse(isPaused(address(USDC_VAULT)));

        vm.startPrank(0xB1345E7A4D35FB3E6bF22A32B3741Ae74E5Fba27);
        EULER_FACTORY_GOVERNOR.pause(EULER_VAULT_FACTORY);

        assertTrue(isPaused(address(PT_SUSDE_NOV_VAULT)));
        assertTrue(isPaused(address(USDC_VAULT)));

        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt * 2);
        vm.expectRevert("contract is in read-only mode");
        adapter.supplyCollateral(collateralAmt, 0);

        // Max join/exit are not impacted. Too hard to reliably handle making these return 0
        // **maybe** we could track the expected proxy implementation, but think it's fine for the user tx
        // to just revert.
        {
            (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
            expectArr(assetAmounts, 9_550_569.628998411958529037e18);
            expectArr(liabilityAmounts, 10_968_699.41618e6);

            (assetAmounts, liabilityAmounts) = adapter.maxExit();
            expectArr(assetAmounts, 449_430.371001588041470963e18);
            expectArr(liabilityAmounts, 91_667_065.018571e6);
        }
    }

    function test_euler_hook_revert() public {
        CustomHook customHook = new CustomHook(EULER_VAULT_FACTORY);

        IEVault vault = IEVault(address(PT_SUSDE_NOV_VAULT));
        address governor = vault.governorAdmin();
        vm.startPrank(governor);
        vault.setHookConfig(address(customHook), EulerConstants.OP_DEPOSIT);

        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        deal(address(PT_SUSDE_NOV), address(adapter), collateralAmt * 2);
        vm.expectRevert(CustomHook.CustomError.selector);
        adapter.supplyCollateral(collateralAmt, 0);

        // Under the threshold is allowed. Even though the hook returns '0', functionally the
        // only thing a hook can do is revert.
        adapter.supplyCollateral(1e18, 0);

        // Max join/exit are not impacted. Too hard to reliably handle making these return 0
        // **maybe** we could track the expected proxy implementation, but think it's fine for the user tx
        // to just revert.
        {
            (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
            expectArr(assetAmounts, 9_550_568.628998411958529037e18);
            expectArr(liabilityAmounts, 10_968_699.41618e6);

            (assetAmounts, liabilityAmounts) = adapter.maxExit();
            expectArr(assetAmounts, 449_431.371001588041470963e18);
            expectArr(liabilityAmounts, 91_667_065.018571e6);
        }
    }
}
