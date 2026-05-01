pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReserveConfiguration as AaveReserveConfiguration
} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";

import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterAaveV3 } from "contracts/investments/opal/adapters/OpalAdapterAaveV3.sol";
import { IOpalAdapterAaveV3 } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterAaveV3.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";

contract OpalAdapterAaveV3IsolationModeTestBase is OrigamiTest {
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterAaveV3 internal adapterImpl;
    OpalAdapterAaveV3 internal adapter;

    address internal manager = makeAddr("manager");

    address internal constant POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    IAavePool internal constant POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // Tether Gold
    IERC20 internal constant XAUT = IERC20(0x68749665FF8D2d112Fa859AA293F07A622782F38);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant DTOKEN_USDC = 0x72E95b8931767C79bA4EeE721354d6E99a61D004;
    address internal constant ATOKEN_XAUT = 0x8A2b6f94Ff3A89a03E8c02Ee92b55aF90c9454A2;

    uint256 internal constant USDC_MAX_BORROW_LTV = 0.75e18;
    uint8 internal constant EMODE_NONE = 0;
    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.9e18; // 90%

    function setUp() public virtual {
        fork("mainnet", 23_894_429);

        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new OpalAdapterAaveV3("AAVEV3.1");
        vm.label(address(adapterImpl), "AAVEV3.1 [IMPL]");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        bytes memory immutableArgs =
            adapterImpl.encodeImmutableArgs(POOL_ADDRESS_PROVIDER, mkArray(address(XAUT)), address(USDC));
        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[XAUT]/[USDC] (iso)", immutableArgs)
        );
        vm.label(address(adapter), "AAVEV3.1 [INST]");
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, EMODE_NONE, MAX_LOAN_UR_ON_JOIN));

        // Increase the isolation mode debt ceiling by 2500
        {
            vm.startPrank(0x64b761D848206f447Fe2dd461b0c635Ec39EbB27);
            AaveDataTypes.ReserveConfigurationMap memory config = POOL.getConfiguration(address(XAUT));
            config.setDebtCeiling(3_002_500.0e2);
            POOL.setConfiguration(address(XAUT), config);
            vm.stopPrank();
        }
    }

    function checkExpectedBs(uint256 collateralAmount, uint256 debtAmount) internal view {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        assertEq(totalAssets.length, 1);
        assertEq(totalAssets[0], collateralAmount);
        assertEq(totalLiabilities.length, 1);
        assertEq(totalLiabilities[0], debtAmount);
    }
}

contract OpalAdapterAaveV3IsolationModeTest is OpalAdapterAaveV3IsolationModeTestBase {
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;
    error DebtCeilingExceeded();
    error LtvValidationFailed();
    error AssetNotBorrowableInIsolation();

    function test_initialization() public view {
        assertEq(adapter.owner(), origamiMultisig);
        assertEq(adapter.implTypeAndVersion(), "AAVEV3.1");
        assertEq(adapter.manager(), manager);
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.description(), "[XAUT]/[USDC] (iso)");
        assertEq(adapter.referralCode(), 0);
        assertEq(address(adapter.aavePoolAddressProvider()), POOL_ADDRESS_PROVIDER);
        assertEq(address(adapter.aavePool()), address(POOL));
        assertEq(adapter.loanToken(), address(USDC));
        assertEq(adapter.aaveDToken(), DTOKEN_USDC);
        assertEq(adapter.numCollateralTokens(), 1);
        address[] memory tokens = adapter.collateralTokens();
        expectArr(tokens, mkArray(address(XAUT)));
        tokens = adapter.aaveATokens();
        expectArr(tokens, mkArray(ATOKEN_XAUT));
        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        expectArr(assetTokens, mkArray(address(XAUT)));
        expectArr(liabilityTokens, address(USDC));

        assertEq(adapter.maxSafeLtv(), 0); // unknown until the first position is added
        assertEq(adapter.liquidationLtv(), 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), MAX_LOAN_UR_ON_JOIN);

        bytes32 expectedGroupId = hex"0000000000000000000000002f39d218133afab8f2b819b1066c7e434ad94e9e";
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        expectArr(assetGroupIds, expectedGroupId);
        expectArr(liabilityGroupIds, expectedGroupId);

        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.79231726715335689e18);

        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965268e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 4_367_195_011.684865e6);
            assertEq(borrowMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
            assertEq(borrowMetrics.availableSupply, 1_007_767_772.112156e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        {
            (
                IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,
                IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 1);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 2294.965268e6);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
        }

        assertEq(POOL.getUserEMode(address(adapter)), EMODE_NONE);

        assertEq(USDC.allowance(address(adapter), address(POOL)), type(uint256).max);
        assertEq(XAUT.allowance(address(adapter), address(POOL)), type(uint256).max, "XAUT Allowance");

        checkExpectedBs(0, 0);

        assertEq(adapter.aavePool().getEModeCategoryData(EMODE_NONE).label, "");
        adapter.validateLtvInRange(0, USDC_MAX_BORROW_LTV); // no-op

        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
        expectArr(assetAmounts, 2705.034732e6);
        expectArr(liabilityAmounts, 2500.51e6);

        (assetAmounts, liabilityAmounts) = adapter.maxExit();
        expectArr(assetAmounts, 2294.965268e6);
        expectArr(liabilityAmounts, 3_844_671_129.759917e6);
    }

    function supplyAndSetAsCollateral() internal {
        deal(address(XAUT), address(adapter), 1);
        vm.prank(manager);
        adapter.supplyCollateral(address(XAUT), 1, 0);

        vm.prank(origamiMultisig);
        adapter.setUserUseReserveAsCollateral(address(XAUT), true);
    }

    function test_join_fail_notAsCollateral() public {
        // This market needs the collateral to be supplied first and explicitly set
        vm.startPrank(manager);
        uint256 collateralAmt = 1e6;
        uint256 borrowAmt = 2000e6;
        deal(address(XAUT), address(manager), collateralAmt);
        XAUT.approve(address(adapter), collateralAmt);

        vm.expectRevert(LtvValidationFailed.selector);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);
    }

    function test_join_success() public {
        supplyAndSetAsCollateral();

        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 2705.034731e6);
        expectArr(liabilities, 2500.51e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 2294.965269e6);
        expectArr(liabilities, 3_844_671_129.759917e6);

        vm.startPrank(manager);
        uint256 collateralAmt = 1e6;
        uint256 borrowAmt = 2000e6;
        deal(address(XAUT), address(manager), collateralAmt);
        XAUT.approve(address(adapter), collateralAmt);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt + 1, borrowAmt + 1);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.476919123095187663e18);
        assertEq(adapter.healthFactor(), 1.572593682409980617e18);
        adapter.validateLtvInRange(0, USDC_MAX_BORROW_LTV);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 2704.034731e6);
        expectArr(liabilities, 500.51e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 2295.965269e6);
        expectArr(liabilities, 3_844_673_129.759917e6);
    }

    function test_maxJoin_success() public {
        supplyAndSetAsCollateral();

        // Join Metrics
        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965269e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 4_367_195_011.684865e6);
            assertEq(borrowMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
            assertEq(borrowMetrics.availableSupply, 1_007_767_772.112156e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        // Exit Metrics
        {
            (
                IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,
                IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 1);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 2294.965269e6);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
        }

        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();

        uint256 collateralAmt = liabilities[0] / 2000;
        uint256 borrowAmt = liabilities[0];
        assertEq(collateralAmt, 1.250255e6);
        assertEq(borrowAmt, 2500.51e6);

        vm.startPrank(manager);
        deal(address(XAUT), address(manager), collateralAmt);
        XAUT.approve(address(adapter), collateralAmt);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt + 1, borrowAmt + 2);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.476919218700774896e18);
        assertEq(adapter.healthFactor(), 1.572593367160067025e18);
        adapter.validateLtvInRange(0, USDC_MAX_BORROW_LTV);

        // Join Metrics
        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2296.215524e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 4_367_195_011.684866e6);
            assertEq(borrowMetrics.alreadyBorrowed, 3_844_673_630.269918e6);
            assertEq(borrowMetrics.availableSupply, 1_007_765_271.602156e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 3_002_500e6);
        }

        // Exit Metrics
        {
            (
                IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,
                IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 1);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 2296.215524e6);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 3_844_673_630.269918e6);
        }

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 2703.784476e6);
        expectArr(liabilities, 0);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 2296.215524e6);
        expectArr(liabilities, 3_844_673_630.269918e6);
    }

    function test_maxJoin_fail_overDebtCeiling() public {
        supplyAndSetAsCollateral();

        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965269e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 4_367_195_011.684865e6);
            assertEq(borrowMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
            assertEq(borrowMetrics.availableSupply, 1_007_767_772.112156e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        (, uint256[] memory liabilities) = adapter.maxJoin();

        uint256 collateralAmt = liabilities[0] / 2000;
        uint256 borrowAmt = liabilities[0];
        assertEq(collateralAmt, 1.250255e6);
        assertEq(borrowAmt, 2500.51e6);

        vm.startPrank(manager);
        deal(address(XAUT), address(manager), collateralAmt);
        XAUT.approve(address(adapter), collateralAmt);

        vm.expectRevert(DebtCeilingExceeded.selector);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt + 0.01e6), alice);
    }

    function test_maxJoin_smallSupply() public {
        supplyAndSetAsCollateral();

        vm.mockCall(address(USDC), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(1000e6));
        vm.mockCall(address(DTOKEN_USDC), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1100e6));

        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965269e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 1890e6);
            assertEq(borrowMetrics.alreadyBorrowed, 1100e6);
            assertEq(borrowMetrics.availableSupply, 1000e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        // Now capped to the 90% UR
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        assertEq(assets[0], 2705.034731e6);
        assertEq(liabilities[0], 790.0e6);

        // Update so the max UR is 100%
        vm.prank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);

        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965269e6);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, type(uint256).max);
            assertEq(borrowMetrics.alreadyBorrowed, 1100e6);
            assertEq(borrowMetrics.availableSupply, 1000e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        // Now capped to the available supply
        (assets, liabilities) = adapter.maxJoin();
        assertEq(assets[0], 2705.034731e6);
        assertEq(liabilities[0], 1000e6);
    }

    function test_exit_success() public {
        supplyAndSetAsCollateral();
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();

        uint256 collateralAmt = liabilities[0] / 2000;
        uint256 borrowAmt = liabilities[0];
        vm.startPrank(manager);
        deal(address(XAUT), address(manager), collateralAmt);
        XAUT.approve(address(adapter), collateralAmt);
        adapter.join(mkArray(collateralAmt), mkArray(borrowAmt), alice);

        {
            IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
            assertEq(details.totalCollateralBase, 5241.8858184e8);
            assertEq(details.totalDebtBase, 2499.95608903e8);
            assertEq(details.availableBorrowsBase, 1169.36398385e8);
            assertEq(details.liquidationLtv, 0.75e18);
            assertEq(details.maxSafeLtv, 0.7e18);
            assertEq(details.healthFactor, 1.572593367160067025e18);
            assertEq(details.currentLtv, 0.476919218700774896e18);
            assertEq(adapter.currentLtv(), details.currentLtv);
            assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
            assertEq(adapter.liquidationLtv(), details.liquidationLtv);
        }

        (assets, liabilities) = adapter.maxExit();
        assertEq(assets[0], 2296.215524e6);
        assertEq(liabilities[0], 3_844_673_630.269918e6);

        deal(address(USDC), address(manager), borrowAmt + 2);
        USDC.approve(address(adapter), borrowAmt + 2);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(collateralAmt + 1), mkArray(borrowAmt + 2));
        adapter.exit(mkArray(collateralAmt + 1), mkArray(borrowAmt + 2), alice);

        checkExpectedBs(0, 0);

        {
            IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
            assertEq(details.totalCollateralBase, 0);
            assertEq(details.totalDebtBase, 0);
            assertEq(details.availableBorrowsBase, 0);
            assertEq(details.liquidationLtv, 0);
            assertEq(details.maxSafeLtv, 0);
            assertEq(details.healthFactor, type(uint256).max);
            assertEq(details.currentLtv, 0);
            assertEq(adapter.currentLtv(), details.currentLtv);
            assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
            assertEq(adapter.liquidationLtv(), details.liquidationLtv);
        }
    }

    function test_fail_nonIsoBorrow() public {
        // Set so USDC isn't borrowable in isolation mode
        {
            vm.startPrank(0x64b761D848206f447Fe2dd461b0c635Ec39EbB27);
            AaveDataTypes.ReserveConfigurationMap memory config = POOL.getConfiguration(address(USDC));
            config.setBorrowableInIsolation(false);
            POOL.setConfiguration(address(USDC), config);
            vm.stopPrank();
        }

        supplyAndSetAsCollateral();

        // Join Metrics
        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 1);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 5000e6);
            assertEq(supplyMetrics[0].alreadySupplied, 2294.965269e6);

            assertTrue(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 4_367_195_011.684865e6);
            assertEq(borrowMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
            assertEq(borrowMetrics.availableSupply, 1_007_767_772.112156e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 3_002_500e6);
            assertEq(borrowMetrics.isolationModeTotalDebt, 2_999_999.49e6);
        }

        // Exit Metrics
        {
            (
                IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,
                IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 1);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 2294.965269e6);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 3_844_671_129.759917e6);
        }

        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 2705.034731e6);
        expectArr(liabilities, 0);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 2294.965269e6);
        expectArr(liabilities, 3_844_671_129.759917e6);

        vm.startPrank(manager);
        deal(address(XAUT), address(manager), 1e6);
        XAUT.approve(address(adapter), 1e6);

        vm.expectRevert(AssetNotBorrowableInIsolation.selector);
        adapter.join(mkArray(1e6), mkArray(1e6), alice);
    }
}
