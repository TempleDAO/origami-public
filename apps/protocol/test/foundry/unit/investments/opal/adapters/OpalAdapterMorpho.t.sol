pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterMorpho } from "contracts/investments/opal/adapters/OpalAdapterMorpho.sol";
import { IOpalAdapterMorpho } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterMorpho.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import {
    IMorpho,
    Id as MorphoMarketId,
    MarketParams as MorphoMarketParams
} from "@morpho-org/morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "@morpho-org/morpho-blue/src/libraries/MarketParamsLib.sol";
import { LibCall } from "solady/utils/LibCall.sol";
import { stdError } from "forge-std/StdError.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { Call, IOrigamiBundler } from "contracts/interfaces/common/bundler/IOrigamiBundler.sol";
import { OrigamiBundler } from "contracts/common/bundler/OrigamiBundler.sol";
import { OrigamiBundlerTestUtils } from "test/foundry/unit/common/bundler/OrigamiBundlerTestUtils.t.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import {
    IOrigamiBundlerPluginEntryPoint
} from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPluginEntryPoint.sol";
import { OrigamiBundlerPluginEntryPoint } from "contracts/common/bundler/plugins/OrigamiBundlerPluginEntryPoint.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

contract OpalAdapterMorphoTestBase is OrigamiTest, OrigamiBundlerTestUtils {
    OpalAdapterFactory internal adapterFactory;
    OpalAdapterMorpho internal adapterImpl;

    OpalAdapterMorpho internal adapter;
    OrigamiBundlerPluginEntryPoint internal entryPointPlugin;

    IERC20 internal daiToken;
    IERC20 internal sUsdeToken;

    address internal manager;

    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant MORPHO_MARKET_ORACLE = 0x5D916980D5Ae1737a8330Bf24dF812b2911Aae25;
    address internal constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 internal constant MORPHO_MARKET_LLTV = 0.915e18; // 91.5%
    uint96 internal constant MAX_SAFE_LLTV = 0.9e18; // 90%

    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.925e18; // 92.5%

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SUSDE_ADDRESS = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        fork("mainnet", 23_323_025);

        daiToken = IERC20(DAI_ADDRESS);
        sUsdeToken = IERC20(SUSDE_ADDRESS);

        entryPointPlugin = new OrigamiBundlerPluginEntryPoint(origamiMultisig, PERMIT2_ADDRESS, WETH_ADDRESS);

        manager = address(new OrigamiBundler());
        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new OpalAdapterMorpho("MORPHO.1");
        vm.label(address(adapterImpl), "MORPHO.1 [IMPL]");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
            MORPHO,
            MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: DAI_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: MORPHO_MARKET_LLTV
            })
        );
        vm.startPrank(manager);
        adapter =
            OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "[sUSDe] / [DAI]", immutableArgs));
        vm.label(address(adapter), "MORPHO.1 [INST]");
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, MAX_SAFE_LLTV, MAX_LOAN_UR_ON_JOIN));

        supplyCapitalIntoMorpho(1000e18);
        vm.stopPrank();

        vm.startPrank(origamiMultisig);
        entryPointPlugin.setBundlerApproved(address(manager), true);
        vm.stopPrank();
    }

    function checkExpectedBs(uint256 collateralAmount, uint256 debtAmount) internal view {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        assertEq(totalAssets.length, 1);
        assertEq(totalAssets[0], collateralAmount);
        assertEq(totalLiabilities.length, 1);
        assertEq(totalLiabilities[0], debtAmount);
    }

    function supplyCapitalIntoMorpho(uint256 amount) internal {
        deal(address(daiToken), origamiMultisig, amount);
        vm.startPrank(origamiMultisig);
        daiToken.approve(MORPHO, amount);
        IMorpho(MORPHO).supply(adapter.getMarketParams(), amount, 0, origamiMultisig, "");
        vm.stopPrank();
    }
}

contract OpalAdapterMorphoTestAdmin is OpalAdapterMorphoTestBase {
    using MarketParamsLib for MorphoMarketParams;

    function test_initialization() public view {
        assertEq(adapter.implTypeAndVersion(), "MORPHO.1");
        assertEq(adapter.manager(), manager);
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.description(), "[sUSDe] / [DAI]");
        assertEq(address(adapter.morpho()), MORPHO);
        assertEq(adapter.collateralToken(), SUSDE_ADDRESS);
        assertEq(adapter.loanToken(), DAI_ADDRESS);
        assertEq(address(adapter.morphoOracle()), MORPHO_MARKET_ORACLE);
        assertEq(address(adapter.morphoIrm()), MORPHO_MARKET_IRM);
        assertEq(adapter.morphoLltv(), MORPHO_MARKET_LLTV);
        assertEq(
            MorphoMarketId.unwrap(adapter.morphoMarketId()),
            hex"1247f1c237eceae0602eab1470a5061a6dd8f734ba88c7cdc5d6109fb0026b28"
        );

        bytes32 expectedGroupId = hex"6d11803dd5153a97fae6ce07d34bc34fb4effd6bd58be8dddd71fcb332d734c0";
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        expectArr(assetGroupIds, expectedGroupId);
        expectArr(liabilityGroupIds, expectedGroupId);

        assertEq(sUsdeToken.allowance(address(adapter), MORPHO), type(uint256).max);
        assertEq(daiToken.allowance(address(adapter), MORPHO), type(uint256).max);

        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        assertEq(assetTokens.length, 1);
        assertEq(assetTokens[0], SUSDE_ADDRESS);
        assertEq(liabilityTokens.length, 1);
        assertEq(liabilityTokens[0], DAI_ADDRESS);

        checkExpectedBs(0, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.maxSafeLtv(), MAX_SAFE_LLTV);
        assertEq(adapter.liquidationLtv(), MORPHO_MARKET_LLTV);
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), MAX_LOAN_UR_ON_JOIN);
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.906111275954098764e18);

        {
            (IOpalAdapterMorpho.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertEq(borrowMetrics.alreadyBorrowed, 3_990_460.135922640012519302e18);
            assertEq(borrowMetrics.totalSupply, 4_403_940.489230581349202225e18);
            assertEq(borrowMetrics.joinBorrowCap, 4_073_644.952538287748012058e18);
        }

        {
            (
                IOpalAdapterMorpho.AssetWithdrawMetrics memory withdrawMetrics,
                IOpalAdapterMorpho.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.availableSupply, 15_012_830.937100485667852698e18);
            assertEq(repayMetrics.totalDebt, 3_990_460.135922640012519302e18);
        }

        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max);
        expectArr(liabilities, 83_184.816615647735492756e18);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 15_012_830.937100485667852698e18);
        expectArr(liabilities, 3_990_460.135922640012519302e18);
    }

    function test_initialize_fail_sameTokens() public {
        bytes memory immutableArgs = abi.encodePacked(
            MORPHO,
            SUSDE_ADDRESS,
            SUSDE_ADDRESS,
            MORPHO_MARKET_ORACLE,
            MORPHO_MARKET_IRM,
            MORPHO_MARKET_LLTV,
            hex"1247f1c237eceae0602eab1470a5061a6dd8f734ba88c7cdc5d6109fb0026b28"
        );
        adapter = OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "sUSDe / DAI", immutableArgs));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, SUSDE_ADDRESS));
        adapter.initialize(abi.encode(origamiMultisig, MAX_SAFE_LLTV, 1e18 + 1));
    }

    function test_initialize_fail() public {
        vm.startPrank(manager);

        // max loan UR too high
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
            MORPHO,
            MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: DAI_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: MORPHO_MARKET_LLTV
            })
        );
        adapter = OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "sUSDe / DAI", immutableArgs));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(abi.encode(origamiMultisig, MAX_SAFE_LLTV, 1e18 + 1));

        // Bad market
        immutableArgs = adapterImpl.encodeImmutableArgs(
            MORPHO,
            MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: DAI_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: 0.99e18 // LLTV doesn't exist
            })
        );
        adapter = OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "sUSDe / DAI", immutableArgs));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(abi.encode(origamiMultisig, MAX_SAFE_LLTV, 1e18));

        // not safe maxSafeLTV
        immutableArgs = adapterImpl.encodeImmutableArgs(
            MORPHO,
            MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: DAI_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: MORPHO_MARKET_LLTV
            })
        );
        adapter = OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "sUSDe / DAI", immutableArgs));
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(abi.encode(origamiMultisig, MORPHO_MARKET_LLTV, MAX_LOAN_UR_ON_JOIN));
    }

    function test_initialize_fail_badId() public {
        vm.startPrank(manager);

        // bad market id
        MorphoMarketParams memory params = MorphoMarketParams({
            collateralToken: SUSDE_ADDRESS,
            loanToken: DAI_ADDRESS,
            oracle: MORPHO_MARKET_ORACLE,
            irm: MORPHO_MARKET_IRM,
            lltv: MORPHO_MARKET_LLTV
        });

        bytes memory immutableArgs = abi.encodePacked(
            MORPHO,
            params.collateralToken,
            params.loanToken,
            params.oracle,
            params.irm,
            params.lltv,
            bytes32(uint256(123))
        );
        adapter = OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "sUSDe / DAI", immutableArgs));
        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, MAX_SAFE_LLTV, MAX_LOAN_UR_ON_JOIN);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(initArgs);
    }

    function test_encodeImmutableArgs_fail_sameAsset() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, SUSDE_ADDRESS));
        adapterImpl.encodeImmutableArgs(
            MORPHO,
            MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: SUSDE_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: 0.99e18 // LLTV doesn't exist
            })
        );
    }

    function test_balanceSheet_noDirectDonations() public {
        deal(address(sUsdeToken), address(adapter), 420.69e18);
        deal(address(daiToken), address(adapter), 123e18);
        checkExpectedBs(0, 0);
    }

    function test_balanceSheet_collateralDonationsAreCounted() public {
        vm.startPrank(alice);
        deal(address(sUsdeToken), alice, 100e18);
        sUsdeToken.approve(MORPHO, 100e18);

        // Supply on behalf of the adapter
        IMorpho(MORPHO)
            .supplyCollateral(
                MorphoMarketParams({
                collateralToken: SUSDE_ADDRESS,
                loanToken: DAI_ADDRESS,
                oracle: MORPHO_MARKET_ORACLE,
                irm: MORPHO_MARKET_IRM,
                lltv: MORPHO_MARKET_LLTV
            }),
                100e18,
                address(adapter),
                ""
            );
        checkExpectedBs(100e18, 0);
    }

    function test_setMaxSafeLtv_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.setMaxSafeLtv(MORPHO_MARKET_LLTV);
    }

    function test_setMaxSafeLtv_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterMorpho.MaxSafeLtvSet(MORPHO_MARKET_LLTV - 1);
        adapter.setMaxSafeLtv(MORPHO_MARKET_LLTV - 1);
        assertEq(adapter.maxSafeLtv(), MORPHO_MARKET_LLTV - 1);
    }

    function test_setMaxLoanUtilizationRatioOnJoin_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18 + 1);
    }

    function test_setMaxLoanUtilizationRatioOnJoin_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterMorpho.MaxLoanUtilizationRatioOnJoinSet(1e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), 1e18);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IOpalAdapterMorpho).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOpalAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(adapter.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OpalAdapterMorphoTestAccess is OpalAdapterMorphoTestBase {
    function test_access_setMaxSafeLtv() public {
        expectElevatedAccess();
        adapter.setMaxSafeLtv(0);
    }

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
        adapter.supplyCollateral(0, 0, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.supplyCollateral(0, 0, "");
    }

    function test_access_onMorphoSupplyCollateral() public {
        expectElevatedAccess();
        adapter.onMorphoSupplyCollateral(0, "");

        expectNoAccess(origamiMultisig);
        adapter.onMorphoSupplyCollateral(0, "");
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
        adapter.borrow(0, 0, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.borrow(0, 0, alice);
    }

    function test_access_repay() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.repay(0, 0, 0, "");

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.repay(0, 0, 0, "");
    }

    function test_access_onMorphoRepay() public {
        expectElevatedAccess();
        adapter.onMorphoRepay(0, "");

        expectNoAccess(origamiMultisig);
        adapter.onMorphoRepay(0, "");
    }
}

contract OpalAdapterMorphoTestJoinExit is OpalAdapterMorphoTestBase {
    function test_join_fail_wrongLength() public {
        vm.startPrank(manager);

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
        sUsdeToken.approve(address(adapter), 123e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        adapter.join(mkArray(123e18), mkArray(0), alice);
    }

    function test_join_success() public {
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max);
        expectArr(liabilities, 83_184.816615647735492756e18);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 15_012_830.937100485667852698e18);
        expectArr(liabilities, 3_990_460.135922640012519302e18);

        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt, borrowAmt + 1);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.469258973608895033e18);
        assertEq(adapter.healthFactor(), 1.949882797047177721e18);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max);
        expectArr(liabilities, 83_115.816615647735492756e18);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 15_012_953.937100485667852698e18);
        expectArr(liabilities, 3_990_529.135922640012519302e18);
    }

    function test_join_someCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 0;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt, borrowAmt);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_join_zeroCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 0;
        uint256 borrowAmt = 0;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt, borrowAmt);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_join_zeroCollateral_someBorrow() public {
        vm.startPrank(manager);

        // Do an initial join first
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 100e6;
        {
            deal(address(sUsdeToken), manager, collateralAmt);
            sUsdeToken.approve(address(adapter), collateralAmt);
            vm.expectEmit(address(adapter));
            emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
            adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        }

        collateralAmt = 0;
        borrowAmt = 1e18;
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overSafeLtv() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 134e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.911314528457854121e18, 0, MAX_SAFE_LLTV)
        );
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_withBorrow() public {
        vm.startPrank(manager);
        adapter.maxJoin();
        uint256 collateralAmt = 100_000e18;
        uint256 borrowAmt = 83_185e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.925000041640969653e18, 0, MAX_LOAN_UR_ON_JOIN
            )
        );
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_zeroBorrow() public {
        vm.startPrank(origamiMultisig);
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.906111275954098764e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(0.8e18);

        vm.startPrank(manager);
        adapter.maxJoin();
        uint256 collateralAmt = 1e18;
        uint256 borrowAmt = 0;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        checkExpectedBs(collateralAmt, borrowAmt);
    }

    function test_join_fail_overLiquidationLtv() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 136e18; // sUSDe ~= 1.195 DAI
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);

        vm.expectRevert("insufficient collateral");
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_exit_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18, 123e18), mkArray(123e18), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18), mkArray(123e18, 123e18), alice);
    }

    function test_exit_fail_notEnough() public {
        vm.startPrank(manager);
        vm.expectRevert("Dai/insufficient-balance");
        adapter.exit(mkArray(1), mkArray(123e18), alice);
    }

    function test_exit_success() public {
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max);
        expectArr(liabilities, 83_184.816615647735492756e18);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 15_012_830.937100485667852698e18);
        expectArr(liabilities, 3_990_460.135922640012519302e18);

        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e18;
        uint256 withdrawAmt = 20e18;
        deal(address(daiToken), manager, repayAmt);
        daiToken.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt + 1);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(daiToken.balanceOf(manager), 0);
        assertEq(sUsdeToken.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.29237072395387466e18);
        assertEq(adapter.healthFactor(), 3.129588310436831988e18);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, type(uint256).max);
        expectArr(liabilities, 83_148.816615647735492756e18);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 15_012_933.937100485667852698e18);
        expectArr(liabilities, 3_990_496.135922640012519302e18);
    }

    function test_exit_zeroRepay_someWithdrawal() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 0;
        uint256 withdrawAmt = 20e18;
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt + 1);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(daiToken.balanceOf(manager), 0);
        assertEq(sUsdeToken.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.560377220911593097e18);
        assertEq(adapter.healthFactor(), 1.632828683706173215e18);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_exit_zeroRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 0;
        uint256 withdrawAmt = 0;
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt - withdrawAmt, borrowAmt - repayAmt + 1);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(daiToken.balanceOf(manager), 0);
        assertEq(sUsdeToken.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0.469258973608895033e18);
        assertEq(adapter.healthFactor(), 1.949882797047177721e18);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_exit_someRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e18;
        uint256 withdrawAmt = 0;
        deal(address(daiToken), manager, repayAmt);
        daiToken.approve(address(adapter), repayAmt);
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);
    }

    function test_exit_repayTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 70e18;
        uint256 withdrawAmt = collateralAmt;
        deal(address(daiToken), manager, repayAmt);
        daiToken.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);

        checkExpectedBs(0, 0);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(daiToken.balanceOf(manager), 0);
        assertEq(sUsdeToken.balanceOf(alice), withdrawAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_exit_fail_overSafeLtv() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 130e18;
        uint256 borrowAmt = 135e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 10e18;
        uint256 withdrawAmt = 15e18;
        deal(address(daiToken), manager, repayAmt);
        daiToken.approve(address(adapter), repayAmt);
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.909244703117424213e18, 0, MAX_SAFE_LLTV)
        );
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);
    }

    function test_exit_withdrawTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 130e18;
        uint256 borrowAmt = 135e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        uint256 repayAmt = 150e18;
        uint256 withdrawAmt = 500e18;
        deal(address(daiToken), manager, repayAmt);
        daiToken.approve(address(adapter), repayAmt);
        vm.expectRevert(stdError.arithmeticError); // morpho error
        adapter.exit(mkArray(withdrawAmt), mkArray(repayAmt), alice);
    }
}

contract OpalAdapterMorphoTestMaxJoinExit is OpalAdapterMorphoTestBase {
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

    function doJoin() internal {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        uint256 borrowAmt = 69e18;
        deal(address(sUsdeToken), manager, collateralAmt);
        sUsdeToken.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
        vm.stopPrank();
    }

    function test_maxJoin_default() public {
        expectMaxJoin(type(uint256).max, 83_184.816615647735492756e18);
        doJoin();
        expectMaxJoin(type(uint256).max, 83_115.816615647735492756e18);
        skip(1 days);
        expectMaxJoin(type(uint256).max, 83_041.765797899449712539e18);
    }

    function test_maxJoin_noMaxUr() public {
        vm.startPrank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);

        expectMaxJoin(type(uint256).max, 413_480.353307941336682923e18);
        doJoin();
        expectMaxJoin(type(uint256).max, 413_411.353307941336682923e18);
        skip(1 days);
        expectMaxJoin(type(uint256).max, 413_411.353307941336682923e18);
    }

    function test_maxJoin_lowMaxUr() public {
        expectMaxJoin(type(uint256).max, 83_184.816615647735492756e18);
        doJoin();

        vm.startPrank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(0.25e18);

        expectMaxJoin(type(uint256).max, 0);
        skip(1 days);
        expectMaxJoin(type(uint256).max, 0);
    }

    function test_maxExit_default() public {
        expectMaxExit(15_012_830.937100485667852698e18, 3_990_460.135922640012519302e18);
        doJoin();
        expectMaxExit(15_012_953.937100485667852698e18, 3_990_529.135922640012519302e18);
        skip(1 days);
        expectMaxExit(15_012_953.937100485667852698e18, 3_991_516.480159283822922196e18);
    }
}

contract OpalAdapterMorphoTestBundlerActions is OpalAdapterMorphoTestBase {
    function test_supplyCollateral_zeroAmt() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 0;
        vm.expectRevert("zero assets"); // morpho error
        adapter.supplyCollateral(collateralAmt, 0, "");

        // No-op if under the min
        adapter.supplyCollateral(collateralAmt, 1, "");
        checkExpectedBs(collateralAmt, 0);
    }

    function test_supplyCollateral_specifiedAmt() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0, ""), collateralAmt);
        checkExpectedBs(collateralAmt, 0);
    }

    function test_supplyCollateral_max_overThreshold() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt);
        assertEq(adapter.supplyCollateral(type(uint256).max, collateralAmt, ""), collateralAmt);
        checkExpectedBs(collateralAmt, 0);
    }

    function test_supplyCollateral_max_underThreshold() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt);
        assertEq(adapter.supplyCollateral(type(uint256).max, collateralAmt + 1, ""), 0);
        checkExpectedBs(0, 0);
    }

    function test_supplyCollateral_withCallback_failWhenCalledDirectly() public {
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt);

        Call[] memory innerBundle = new Call[](1);
        innerBundle[0] =
            createCall(adapter, abi.encodeWithSelector(IOpalAdapterMorpho.withdrawCollateral.selector, 25e18, alice));
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.IncorrectReenterHash.selector));
        adapter.supplyCollateral(collateralAmt, 0, encodedInnerBundle);
    }

    function test_supplyCollateral_withCallback_1Deep() public {
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt);

        Call[] memory innerBundle = new Call[](2);
        innerBundle[0] =
            createCall(adapter, abi.encodeWithSelector(IOpalAdapterMorpho.withdrawCollateral.selector, 25e18, alice));
        innerBundle[1] =
            createCall(adapter, abi.encodeWithSelector(IOpalAdapterMorpho.withdrawCollateral.selector, 15e18, bob));
        bytes memory encodedInnerBundle = abi.encode(innerBundle);

        Call[] memory outerBundle = new Call[](1);
        outerBundle[0] = createCall(
            adapter,
            abi.encodeWithSelector(IOpalAdapterMorpho.supplyCollateral.selector, collateralAmt, 0, encodedInnerBundle),
            keccak256(encodedInnerBundle)
        );

        vm.startPrank(origamiMultisig);
        IOrigamiBundler(manager).multicall(outerBundle);

        checkExpectedBs(collateralAmt - 25e18 - 15e18, 0);
    }

    function test_supplyCollateral_withCallback_2Deep() public {
        uint256 collateralAmt = 123e18;

        // Approval for the adapter to pull from overlord
        {
            deal(address(sUsdeToken), overlord, collateralAmt);
            vm.prank(overlord);
            sUsdeToken.approve(address(entryPointPlugin), collateralAmt);
        }

        // (3) Withdraw collateral to alice
        Call[] memory mostInnerBundle = new Call[](1);
        mostInnerBundle[0] =
            createCall(adapter, abi.encodeWithSelector(IOpalAdapterMorpho.withdrawCollateral.selector, 25e18, alice));
        bytes memory encodedMostInnerBundle = abi.encode(mostInnerBundle);

        // (2) transfer collateral from overlord to adapter, supply collateral with callback
        Call[] memory secondMostInnerBundle = new Call[](2);
        secondMostInnerBundle[0] = createCall(
            entryPointPlugin,
            abi.encodeWithSelector(
                IOrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator.selector,
                address(sUsdeToken),
                address(adapter),
                collateralAmt
            )
        );
        secondMostInnerBundle[1] = createCall(
            adapter,
            abi.encodeWithSelector(
                IOpalAdapterMorpho.supplyCollateral.selector, collateralAmt, 0, encodedMostInnerBundle
            ),
            keccak256(encodedMostInnerBundle)
        );
        bytes memory encodedSecondMostInnerBundle = abi.encode(secondMostInnerBundle);

        // (1) supply pre-dealt sUSDe
        deal(address(sUsdeToken), address(adapter), collateralAmt);
        Call[] memory outerBundle = new Call[](1);
        outerBundle[0] = createCall(
            adapter,
            abi.encodeWithSelector(
                IOpalAdapterMorpho.supplyCollateral.selector, collateralAmt, 0, encodedSecondMostInnerBundle
            ),
            keccak256(encodedSecondMostInnerBundle)
        );

        vm.startPrank(overlord);
        IOrigamiBundler(manager).multicall(outerBundle);

        checkExpectedBs(2 * collateralAmt - 25e18, 0);
    }

    function test_onMorphoSupplyCollateral_withCallback_failBundlerUnset() public {
        vm.startPrank(MORPHO);
        vm.expectRevert(abi.encodeWithSelector(LibCall.TargetIsNotContract.selector));
        adapter.onMorphoSupplyCollateral(100e18, abi.encode(new Call[](0)));
    }

    function test_onMorphoSupplyCollateral_badCalldata() public {
        vm.startPrank(MORPHO);
        vm.expectRevert();
        adapter.onMorphoSupplyCollateral(100e18, "foo");
    }

    function test_withdrawCollateral_zeroAmt() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 0;
        vm.expectRevert("zero assets"); // morpho error
        adapter.withdrawCollateral(collateralAmt, alice);
    }

    function test_withdrawCollateral_notEnough() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        vm.expectRevert(stdError.arithmeticError); // morpho error
        adapter.withdrawCollateral(collateralAmt, alice);
    }

    function test_withdrawCollateral_specifiedAmt() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 withdrawAmt = 123e18;
        assertEq(adapter.withdrawCollateral(withdrawAmt, alice), withdrawAmt);
        assertEq(sUsdeToken.balanceOf(alice), withdrawAmt);
        checkExpectedBs(supplyAmt - withdrawAmt, 0);
    }

    function test_withdrawCollateral_max() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        assertEq(adapter.withdrawCollateral(type(uint256).max, alice), supplyAmt);
        assertEq(sUsdeToken.balanceOf(alice), supplyAmt);
        checkExpectedBs(0, 0);
    }

    function test_borrow_notEnoughCollateral() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 1094e18;
        vm.expectRevert("insufficient collateral");
        adapter.borrow(borrowAmt, 0, alice);
    }

    function test_borrow_assets() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 1080e18;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, alice);
        assertEq(borrowedAssets, borrowAmt);
        assertEq(borrowedShares, 0.91926360448124183422727987e27);
        assertEq(daiToken.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.903425537017472698e18);
        assertEq(adapter.healthFactor(), 1.012811750950431065e18);

        // It is actually above the unsafe LTV now
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.903425537017472698e18, 0, MAX_SAFE_LLTV)
        );
        adapter.validateLtvInRange(0, MAX_SAFE_LLTV);
    }

    function test_borrow_shares() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowShares = 0.78e27;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(0, borrowShares, alice);
        assertEq(borrowedAssets, 916.385676419096949497e18);
        assertEq(borrowedShares, borrowShares);
        assertEq(daiToken.balanceOf(alice), 916.385676419096949497e18);
        assertEq(adapter.currentLtv(), 0.766561316513002434e18);
        assertEq(adapter.healthFactor(), 1.193642283127757784e18);

        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.766561316513002434e18, 0.75e18, 0.76e18)
        );
        adapter.validateLtvInRange(0.75e18, 0.76e18);
    }

    function test_borrow_assets_and_shares() public {
        vm.startPrank(manager);
        vm.expectRevert("inconsistent input");
        adapter.borrow(123, 0.78e27, alice);
    }

    function test_borrow_zeroAmount() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        vm.expectRevert("inconsistent input");
        adapter.borrow(0, 0, alice);
    }

    function test_repay_assets_and_shares() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        vm.expectRevert("inconsistent input");
        adapter.repay(borrowAmt, 0, borrowAmt, "");
    }

    function test_repay_assets_tooManyAssets() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        // An extra DAI to start
        deal(address(daiToken), address(adapter), 1e18);

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        adapter.repay(borrowAmt + 1e18, 0, 0, "");

        assertEq(daiToken.balanceOf(address(adapter)), 1e18 - 1);
        checkExpectedBs(supplyAmt, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_assets_exactAssets() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, address(adapter));

        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(borrowAmt, 0, 0, "");
        assertEq(borrowedAssets, repaidAssets);
        assertEq(borrowedShares, repaidShares + 1); // left 1 share dust
        assertEq(adapter.currentLtv(), 1);
        assertEq(adapter.healthFactor(), 915e33);
    }

    function test_repay_assets_partialAssets() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        uint256 repayAmt = 100e18;
        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(repayAmt, 0, 0, "");
        assertEq(repaidAssets, repayAmt);
        assertEq(repaidShares, 0.085117000414929799465488876e27);
        assertEq(adapter.currentLtv(), 0.543728332464219679e18);
        assertEq(adapter.healthFactor(), 1.682825678502254695e18);
        assertEq(daiToken.balanceOf(address(adapter)), 650e18);
    }

    function test_repay_assets_maxAssets_underThreshold() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, address(adapter));

        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(type(uint256).max, borrowAmt, 0, "");
        assertEq(borrowedAssets, repaidAssets);
        assertEq(borrowedShares, repaidShares + 1); // 1 dust of shares left
        assertEq(adapter.currentLtv(), 1);
        assertEq(adapter.healthFactor(), 915e33);
    }

    function test_repay_assets_maxAssets_overThreshold() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(type(uint256).max, borrowAmt + 1, 0, "");
        assertEq(repaidAssets, 0);
        assertEq(repaidShares, 0);
        assertEq(adapter.currentLtv(), 0.627378845151022707e18);
        assertEq(adapter.healthFactor(), 1.458448921368620734e18);
    }

    function test_repay_assets_withCallback_failWhenCalledDirectly() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        uint256 repayAmt = 250e18;

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundler.IncorrectReenterHash.selector));
        adapter.repay(repayAmt, 0, 0, abi.encode(new Call[](0)));
    }

    function test_repay_assets_withCallback_2Deep() public {
        uint256 collateralAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt);
        vm.startPrank(manager);
        adapter.supplyCollateral(collateralAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        uint256 repayAmt = 250e18;

        // Approval for the adapter to pull from overlord
        {
            deal(address(sUsdeToken), overlord, collateralAmt);
            vm.startPrank(overlord);
            sUsdeToken.approve(address(entryPointPlugin), collateralAmt);
        }

        // (3) Withdraw collateral to alice
        Call[] memory mostInnerBundle = new Call[](1);
        mostInnerBundle[0] =
            createCall(adapter, abi.encodeWithSelector(IOpalAdapterMorpho.withdrawCollateral.selector, 25e18, alice));
        bytes memory encodedMostInnerBundle = abi.encode(mostInnerBundle);

        // (2) transfer collateral from overlord to adapter, supply collateral with callback
        Call[] memory secondMostInnerBundle = new Call[](2);
        secondMostInnerBundle[0] = createCall(
            entryPointPlugin,
            abi.encodeWithSelector(
                IOrigamiBundlerPluginEntryPoint.erc20TransferFromInitiator.selector,
                address(sUsdeToken),
                address(adapter),
                collateralAmt
            )
        );
        secondMostInnerBundle[1] = createCall(
            adapter,
            abi.encodeWithSelector(
                IOpalAdapterMorpho.supplyCollateral.selector, collateralAmt, 0, encodedMostInnerBundle
            ),
            keccak256(encodedMostInnerBundle)
        );
        bytes memory encodedSecondMostInnerBundle = abi.encode(secondMostInnerBundle);

        // (1) repay pre-dealt DAI
        deal(address(daiToken), address(adapter), repayAmt);
        Call[] memory outerBundle = new Call[](1);
        outerBundle[0] = createCall(
            adapter,
            abi.encodeWithSelector(IOpalAdapterMorpho.repay.selector, repayAmt, 0, 0, encodedSecondMostInnerBundle),
            keccak256(encodedSecondMostInnerBundle)
        );

        vm.startPrank(overlord);
        IOrigamiBundler(manager).multicall(outerBundle);

        checkExpectedBs(2 * collateralAmt - 25e18, borrowAmt - repayAmt + 1);
    }

    function test_repay_shares_tooManyShares() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        (, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, address(adapter));

        vm.expectRevert(stdError.arithmeticError); // morpho error
        adapter.repay(0, 0, borrowedShares + 1, "");
    }

    function test_repay_shares_exactShares() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, address(adapter));
        deal(DAI_ADDRESS, address(adapter), borrowAmt + 1); // need 1 wei extra

        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(0, 0, borrowedShares, "");
        assertEq(borrowedAssets, repaidAssets - 1);
        assertEq(borrowedShares, repaidShares);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_shares_partialShares() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        adapter.borrow(borrowAmt, 0, address(adapter));

        uint256 repayShares = 0.5e27;
        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(0, 0, repayShares, "");
        assertEq(repaidAssets, 587.426715653267275319e18);
        assertEq(repaidShares, repayShares);
        assertEq(adapter.currentLtv(), 0.135993385847816019e18);
        assertEq(adapter.healthFactor(), 6.728268395522813658e18);
        assertEq(daiToken.balanceOf(address(adapter)), 162.573284346732724681e18);
    }

    function test_repay_shares_maxShares_withDebt() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        uint256 borrowAmt = 750e18;
        (uint256 borrowedAssets, uint256 borrowedShares) = adapter.borrow(borrowAmt, 0, address(adapter));
        deal(DAI_ADDRESS, address(adapter), borrowAmt + 1); // need 1 wei extra

        // minAssets isn't checked when using shares - set to max here
        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(0, type(uint256).max, type(uint256).max, "");
        assertEq(borrowedAssets, repaidAssets - 1);
        assertEq(borrowedShares, repaidShares);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_shares_maxShares_noDebt() public {
        vm.startPrank(manager);
        uint256 supplyAmt = 1000e18;
        deal(address(sUsdeToken), address(adapter), supplyAmt);
        adapter.supplyCollateral(supplyAmt, 0, "");

        // minAssets isn't checked when using shares - set to anything here
        (uint256 repaidAssets, uint256 repaidShares) = adapter.repay(0, 123, type(uint256).max, "");
        assertEq(repaidAssets, 0);
        assertEq(repaidShares, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_onMorphoRepay_withCallback_failBundlerUnset() public {
        vm.startPrank(MORPHO);
        vm.expectRevert(abi.encodeWithSelector(LibCall.TargetIsNotContract.selector));
        adapter.onMorphoRepay(100e18, abi.encode(new Call[](0)));
    }

    function test_validateLtvInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLtvInRange(0.82e18, 0.1e18);
    }

    function test_validateLtvInRange() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0, ""), collateralAmt);

        uint256 borrowAmt = 123e18;
        adapter.borrow(borrowAmt, 0, alice);
        assertEq(adapter.currentLtv(), 0.836505126868030276e18);

        // no-op
        adapter.validateLtvInRange(0.83e18, 0.84e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.836505126868030276e18, 0.82e18, 0.83e18)
        );
        adapter.validateLtvInRange(0.82e18, 0.83e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.836505126868030276e18, 0.84e18, 0.85e18)
        );
        adapter.validateLtvInRange(0.84e18, 0.85e18);

        // Bound by the max safe ltv on the contract
        vm.startPrank(origamiMultisig);
        adapter.setMaxSafeLtv(0.75e18);
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.836505126868030276e18, 0.1e18, 0.75e18)
        );
        adapter.validateLtvInRange(0.1e18, 0.85e18);
    }

    function test_validateLoanUtilizationRatioInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLoanUtilizationRatioInRange(0.82e18, 0.1e18);
    }

    function test_validateLoanUtilizationRatioInRange_rangeChecks() public {
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.906111275954098764e18);

        // no-op
        adapter.validateLoanUtilizationRatioInRange(0.83e18, 0.95e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.906111275954098764e18, 0.83e18, 0.85e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.83e18, 0.85e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.906111275954098764e18, 0.91e18, 0.93e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.91e18, 0.93e18);
    }
}

contract OpalAdapterMorphoTestViews is OpalAdapterMorphoTestBase {
    function test_positionDetails() public {
        vm.startPrank(manager);
        uint256 collateralAmount = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmount);
        assertEq(adapter.supplyCollateral(collateralAmount, 0, ""), collateralAmount);

        uint256 borrowAmt = 123e18;
        adapter.borrow(borrowAmt, 0, alice);

        IOpalAdapterMorpho.MorphoPositionDetails memory details = adapter.positionDetails();
        assertEq(details.collateralSupplied, collateralAmount);
        assertEq(details.liabilityValue, borrowAmt + 1);
        assertEq(details.collateralValueInLiabilityTerms, 147.040342072410123432e18);
        assertEq(details.liquidationLtv, 0.915e18);
        assertEq(details.maxSafeLtv, 0.9e18);
        assertEq(details.currentLtv, 0.836505126868030276e18);
        assertEq(details.healthFactor, 1.093836691026465551e18);

        // liabilityValue value is > 0 and collateralValueInLiabilityTerms is 0
        vm.mockCall(
            MORPHO_MARKET_ORACLE,
            abi.encodeWithSelector(
                0xa035b1fe /*price*/
            ),
            abi.encode(0)
        );
        details = adapter.positionDetails();
        assertEq(details.collateralSupplied, collateralAmount);
        assertEq(details.collateralValueInLiabilityTerms, 0);
        assertEq(details.liabilityValue, borrowAmt + 1);
        assertEq(details.currentLtv, type(uint256).max);
        assertEq(details.healthFactor, 0);

        // liabilityValue value is 0 and collateralSupplied is > 0
        vm.clearMockedCalls();
        deal(address(daiToken), address(adapter), borrowAmt + 1);
        adapter.repay(borrowAmt + 1, 0, 0, "");
        details = adapter.positionDetails();
        assertEq(details.collateralSupplied, collateralAmount);
        assertEq(details.collateralValueInLiabilityTerms, 147.040342072410123432e18);
        assertEq(details.liabilityValue, 0);
        assertEq(details.currentLtv, 0);
        assertEq(details.healthFactor, type(uint256).max);
    }

    function test_currentLtv_noDebt() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0, ""), collateralAmt);
        assertEq(adapter.currentLtv(), 0);
    }

    function test_currentLtv_zeroOraclePrice() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0, ""), collateralAmt);

        uint256 borrowAmt = 123e18;
        adapter.borrow(borrowAmt, 0, alice);

        vm.mockCall(
            MORPHO_MARKET_ORACLE,
            abi.encodeWithSelector(
                0xa035b1fe /*price*/
            ),
            abi.encode(0)
        );
        assertEq(adapter.currentLtv(), type(uint256).max);
    }

    function test_currentLtv_withDebt() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(sUsdeToken), address(adapter), collateralAmt * 2);
        assertEq(adapter.supplyCollateral(collateralAmt, 0, ""), collateralAmt);

        uint256 borrowAmt = 123e18;
        adapter.borrow(borrowAmt, 0, alice);
        assertEq(adapter.currentLtv(), 0.836505126868030276e18);
    }

    function test_liquidationLtv() public view {
        assertEq(adapter.liquidationLtv(), MORPHO_MARKET_LLTV);
    }

    function test_joinMetrics_noMaxUr() public {
        vm.startPrank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);

        (IOpalAdapterMorpho.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
        assertEq(borrowMetrics.alreadyBorrowed, 3_990_460.135922640012519302e18);
        assertEq(borrowMetrics.totalSupply, 4_403_940.489230581349202225e18);
        assertEq(borrowMetrics.joinBorrowCap, type(uint256).max);
    }

    function test_currentLoanTokenUtilizationRatio_noSupply() public {
        MorphoMarketParams memory params = MorphoMarketParams({
            collateralToken: SUSDE_ADDRESS,
            loanToken: DAI_ADDRESS,
            oracle: MORPHO_MARKET_ORACLE,
            irm: MORPHO_MARKET_IRM,
            lltv: 0.385e18 // new LLTV
        });
        IMorpho(MORPHO).createMarket(params);

        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(MORPHO, params);

        vm.startPrank(manager);
        adapter =
            OpalAdapterMorpho(adapterFactory.create(address(adapterImpl), manager, "[sUSDe] / [DAI]", immutableArgs));
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, 0.38e18, MAX_LOAN_UR_ON_JOIN));
        vm.stopPrank();

        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0);
    }
}
