pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ReserveConfiguration as AaveReserveConfiguration
} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { DataTypes as AaveDataTypes } from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import { IPool as IAavePool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { PoolAddressesProvider } from "@aave/core-v3/contracts/protocol/configuration/PoolAddressesProvider.sol";
import {
    IAaveV3RewardsController
} from "contracts/interfaces/external/aave/aave-v3-periphery/IAaveV3RewardsController.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { OpalAdapterFactory } from "contracts/investments/opal/OpalAdapterFactory.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OpalAdapterAaveV3 } from "contracts/investments/opal/adapters/OpalAdapterAaveV3.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IOpalAdapterAaveV3 } from "contracts/interfaces/investments/opal/adapters/IOpalAdapterAaveV3.sol";
import { IOpalAdapter } from "contracts/interfaces/investments/opal/adapters/IOpalAdapter.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { IOrigamiBundlerPlugin } from "contracts/interfaces/common/bundler/plugins/IOrigamiBundlerPlugin.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";

interface IAaveProxy {
    function admin() external view returns (address);
    function implementation() external view returns (address);
    function upgradeTo(address newImplementation) external;
}

contract OpalAdapterAaveV3TestBase is OrigamiTest {
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    error NotEnoughAvailableUserBalance();

    OpalAdapterFactory internal adapterFactory;
    OpalAdapterAaveV3 internal adapterImpl;

    OpalAdapterAaveV3 internal adapter;

    address internal manager = makeAddr("manager");

    address internal constant POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    IAavePool internal constant POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    IERC20 internal constant SUSDE = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 internal constant PT_SUSDE_SEP = IERC20(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77);
    IERC20 internal constant USDE = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal constant DTOKEN_USDC = 0x72E95b8931767C79bA4EeE721354d6E99a61D004;
    address internal constant ATOKEN_SUSDE = 0x4579a27aF00A62C0EB156349f31B345c08386419;
    address internal constant ATOKEN_PT_SUSDE_SEP = 0x5f4a0873a3A02f7C0CB0e13a1d4362a1AD90e751;

    // PT-sUSDe Stablecoins September 2025
    uint8 internal constant EMODE_PT_SUSDE_SEP_2025 = 0x11;
    uint256 internal constant AAVE_EMODE_MAX_BORROW_LTV = 0.9e18;

    uint256 internal constant MAX_LOAN_UR_ON_JOIN = 0.9e18; // 90%

    function setUp() public virtual {
        fork("mainnet", 23_323_025);

        adapterFactory = new OpalAdapterFactory(origamiMultisig);
        adapterImpl = new OpalAdapterAaveV3("AAVEV3.1");
        vm.label(address(adapterImpl), "AAVEV3.1 [IMPL]");
        vm.startPrank(origamiMultisig);
        adapterFactory.addImplementation(address(adapterImpl));

        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
            POOL_ADDRESS_PROVIDER, mkArray(address(SUSDE), address(PT_SUSDE_SEP)), address(USDC)
        );
        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );
        vm.label(address(adapter), "AAVEV3.1 [INST]");
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN));

        vm.stopPrank();
    }

    function checkExpectedBs(uint256 collateral1Amount, uint256 collateral2Amount, uint256 debtAmount) internal view {
        (uint256[] memory totalAssets, uint256[] memory totalLiabilities) = adapter.balanceSheet();
        expectArr(totalAssets, mkArray(collateral1Amount, collateral2Amount));
        expectArr(totalLiabilities, mkArray(debtAmount));
    }

    function supply(IERC20 token, uint256 amount) internal {
        deal(address(token), address(adapter), amount);
        vm.startPrank(manager);
        adapter.supplyCollateral(address(token), amount, 0);
        vm.stopPrank();
    }

    function setConfig(
        address token,
        bool active,
        bool frozen,
        bool borrowingEnabled,
        bool paused,
        uint256 supplyCap,
        uint256 borrowCap
    ) internal {
        address configOwner = 0x64b761D848206f447Fe2dd461b0c635Ec39EbB27;
        vm.startPrank(configOwner);
        AaveDataTypes.ReserveConfigurationMap memory config = POOL.getConfiguration(token);

        config.setActive(active);
        config.setFrozen(frozen);
        config.setBorrowingEnabled(borrowingEnabled);
        config.setPaused(paused);
        config.setSupplyCap(supplyCap);
        config.setBorrowCap(borrowCap);
        POOL.setConfiguration(token, config);
        vm.stopPrank();
    }
}

contract OpalAdapterAaveV3TestAdmin is OpalAdapterAaveV3TestBase {
    error UnderlyingBalanceZero();
    error HealthFactorLowerThanLiquidationThreshold();

    function test_initialization() public view {
        assertEq(adapter.owner(), origamiMultisig);
        assertEq(adapter.implTypeAndVersion(), "AAVEV3.1");
        assertEq(adapter.manager(), manager);
        assertEq(adapter.bundler(), address(0)); // transient
        assertEq(adapter.description(), "[sUSDe,PT-sUSDe-Sep]/[USDC]");
        assertEq(adapter.referralCode(), 0);
        assertEq(address(adapter.aavePoolAddressProvider()), POOL_ADDRESS_PROVIDER);
        assertEq(address(adapter.aavePool()), address(POOL));
        assertEq(adapter.loanToken(), address(USDC));
        assertEq(adapter.aaveDToken(), DTOKEN_USDC);
        assertEq(adapter.numCollateralTokens(), 2);
        address[] memory tokens = adapter.collateralTokens();
        expectArr(tokens, mkArray(address(SUSDE), address(PT_SUSDE_SEP)));
        tokens = adapter.aaveATokens();
        expectArr(tokens, mkArray(ATOKEN_SUSDE, ATOKEN_PT_SUSDE_SEP));
        (address[] memory assetTokens, address[] memory liabilityTokens) = adapter.tokens();
        expectArr(assetTokens, mkArray(address(SUSDE), address(PT_SUSDE_SEP)));
        expectArr(liabilityTokens, address(USDC));

        assertEq(adapter.maxSafeLtv(), 0); // unknown until the first position is added
        assertEq(adapter.liquidationLtv(), 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), MAX_LOAN_UR_ON_JOIN);

        bytes32 expectedGroupId = hex"0000000000000000000000002f39d218133afab8f2b819b1066c7e434ad94e9e";
        (bytes32[] memory assetGroupIds, bytes32[] memory liabilityGroupIds) = adapter.groupIds();
        expectArr(assetGroupIds, expectedGroupId, expectedGroupId);
        expectArr(liabilityGroupIds, expectedGroupId);

        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.832408481174465776e18);

        {
            (
                IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,
                IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics
            ) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 2);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 1_300_000_000e18);
            assertEq(supplyMetrics[0].alreadySupplied, 965_395_991.527189741048024434e18);
            assertFalse(supplyMetrics[1].supplyingDisabled);
            assertEq(supplyMetrics[1].aaveSupplyCap, 2_400_000_000e18);
            assertEq(supplyMetrics[1].alreadySupplied, 2_386_747_546.070550598761661668e18);

            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 5_385_387_636.736599e6);
            assertEq(borrowMetrics.alreadyBorrowed, 4_980_935_936.924065e6);
            assertEq(borrowMetrics.availableSupply, 1_002_828_103.894379e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 0);
            assertEq(borrowMetrics.isolationModeTotalDebt, 0);
        }

        {
            (
                IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,
                IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics
            ) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 2);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 965_395_991.527189741048026755e18);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
            assertEq(withdrawMetrics[1].availableSupply, 2_386_747_546.070550598761661668e18);

            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 4_980_935_936.924065e6);
        }

        assertEq(POOL.getUserEMode(address(adapter)), EMODE_PT_SUSDE_SEP_2025);

        assertEq(USDC.allowance(address(adapter), address(POOL)), type(uint256).max);
        assertEq(SUSDE.allowance(address(adapter), address(POOL)), type(uint256).max);
        assertEq(PT_SUSDE_SEP.allowance(address(adapter), address(POOL)), type(uint256).max);

        checkExpectedBs(0, 0, 0);

        assertEq(
            adapter.aavePool().getEModeCategoryData(EMODE_PT_SUSDE_SEP_2025).label,
            "PT-sUSDe Stablecoins September 2025"
        );
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV); // no-op

        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
        expectArr(assetAmounts, 334_604_008.472810258951975566e18, 13_252_453.929449401238338332e18);
        expectArr(liabilityAmounts, 404_451_699.812534e6);

        (assetAmounts, liabilityAmounts) = adapter.maxExit();
        expectArr(assetAmounts, 965_395_991.527189741048026755e18, 2_386_747_546.070550598761661668e18);
        expectArr(liabilityAmounts, 4_980_935_936.924065e6);
    }

    function test_initialize_zeroEmode() public {
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
            POOL_ADDRESS_PROVIDER, mkArray(address(SUSDE), address(PT_SUSDE_SEP)), address(USDC)
        );
        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );
        adapter.initialize(adapter.encodeInitArgs(origamiMultisig, 0, MAX_LOAN_UR_ON_JOIN));
        assertEq(adapter.aavePool().getEModeCategoryData(0).label, "");
        assertEq(POOL.getUserEMode(address(adapter)), 0);
    }

    // Add one for too much UR

    function test_initialize_fail_maxURTooHigh() public {
        bytes memory immutableArgs = adapterImpl.encodeImmutableArgs(
            POOL_ADDRESS_PROVIDER, mkArray(address(SUSDE), address(PT_SUSDE_SEP)), address(USDC)
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, 1e18 + 1);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_badDToken() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER,
            address(USDC),
            alice, // bad dToken
            uint8(2),
            address(SUSDE),
            ATOKEN_SUSDE,
            address(PT_SUSDE_SEP),
            ATOKEN_PT_SUSDE_SEP
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_missingCollateralToken() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER, address(USDC), DTOKEN_USDC, uint8(2), address(SUSDE), ATOKEN_SUSDE
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert("Address: call to non-contract");
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_badAToken() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER,
            address(USDC),
            DTOKEN_USDC,
            uint8(2),
            address(SUSDE),
            ATOKEN_SUSDE,
            address(PT_SUSDE_SEP),
            alice
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_noAssets() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER,
            address(USDC),
            DTOKEN_USDC,
            uint8(0), // no assets even if encoded below
            address(SUSDE),
            ATOKEN_SUSDE,
            address(PT_SUSDE_SEP),
            ATOKEN_PT_SUSDE_SEP
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_tooManyAssets() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER,
            address(USDC),
            DTOKEN_USDC,
            uint8(6), // too many assets
            address(SUSDE),
            ATOKEN_SUSDE,
            address(PT_SUSDE_SEP),
            ATOKEN_PT_SUSDE_SEP
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.initialize(initArgs);
    }

    function test_initialize_fail_sameAsset() public {
        bytes memory immutableArgs = abi.encodePacked(
            POOL_ADDRESS_PROVIDER, address(USDC), DTOKEN_USDC, uint8(1), address(USDC), ATOKEN_SUSDE
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDC)));
        adapter.initialize(initArgs);
    }

    function test_encodeImmutableArgs_fail_noAssets() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.encodeImmutableArgs(POOL_ADDRESS_PROVIDER, new address[](0), address(USDC));
    }

    function test_encodeImmutableArgs_fail_tooManyAssets() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.encodeImmutableArgs(POOL_ADDRESS_PROVIDER, new address[](6), address(USDC));
    }

    function test_encodeImmutableArgs_fail_sameToken() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(SUSDE)));
        adapter.encodeImmutableArgs(POOL_ADDRESS_PROVIDER, mkArray(address(SUSDE)), address(SUSDE));
    }

    function test_encodeImmutableArgs_fail_badTokens() public {
        // With bad addresses this still 'works', but the initialize fails later.
        bytes memory immutableArgs = adapter.encodeImmutableArgs(POOL_ADDRESS_PROVIDER, new address[](1), alice);
        assertEq(
            immutableArgs,
            abi.encodePacked(
                POOL_ADDRESS_PROVIDER,
                alice, // bad
                address(0), // not found
                uint8(1),
                address(0), // not found
                address(0) // not found
            )
        );

        vm.startPrank(address(manager));
        adapter = OpalAdapterAaveV3(
            adapterFactory.create(address(adapterImpl), address(manager), "[sUSDe,PT-sUSDe-Sep]/[USDC]", immutableArgs)
        );

        bytes memory initArgs = adapter.encodeInitArgs(origamiMultisig, EMODE_PT_SUSDE_SEP_2025, MAX_LOAN_UR_ON_JOIN);
        vm.expectRevert("Address: call to non-contract");
        adapter.initialize(initArgs);
    }

    function test_updateAavePool_fail_sameAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, POOL));
        adapter.updateAavePool();
    }

    function test_updateAavePool_fail_badDToken() public {
        address POOL_PRIME = 0x4e033931ad43597d96D6bcc25c280717730B58B1;

        AaveDataTypes.ReserveDataLegacy memory oldRdSusde = POOL.getReserveData(address(SUSDE));
        vm.mockCall(
            POOL_PRIME,
            abi.encodeWithSelector(IAavePool.getReserveData.selector, address(SUSDE)),
            abi.encode(oldRdSusde)
        );

        AaveDataTypes.ReserveDataLegacy memory oldRdPt = POOL.getReserveData(address(PT_SUSDE_SEP));
        vm.mockCall(
            POOL_PRIME,
            abi.encodeWithSelector(IAavePool.getReserveData.selector, address(PT_SUSDE_SEP)),
            abi.encode(oldRdPt)
        );

        // Update the aave pool (just point it to the prime market)
        {
            PoolAddressesProvider PAP = PoolAddressesProvider(POOL_ADDRESS_PROVIDER);
            vm.prank(PAP.owner());
            PAP.setAddress("POOL", POOL_PRIME);
            assertEq(PAP.getPool(), POOL_PRIME);
        }

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.updateAavePool();
    }

    function test_updateAavePool_fail_badAToken() public {
        address POOL_PRIME = 0x4e033931ad43597d96D6bcc25c280717730B58B1;

        AaveDataTypes.ReserveDataLegacy memory oldRdUsdc = POOL.getReserveData(address(USDC));
        vm.mockCall(
            POOL_PRIME, abi.encodeWithSelector(IAavePool.getReserveData.selector, address(USDC)), abi.encode(oldRdUsdc)
        );

        AaveDataTypes.ReserveDataLegacy memory oldRdSusde = POOL.getReserveData(address(SUSDE));
        vm.mockCall(
            POOL_PRIME,
            abi.encodeWithSelector(IAavePool.getReserveData.selector, address(SUSDE)),
            abi.encode(oldRdSusde)
        );

        // Update the aave pool (just point it to the prime market)
        {
            PoolAddressesProvider PAP = PoolAddressesProvider(POOL_ADDRESS_PROVIDER);
            vm.prank(PAP.owner());
            PAP.setAddress("POOL", POOL_PRIME);
            assertEq(PAP.getPool(), POOL_PRIME);
        }

        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.updateAavePool();
    }

    function test_updateAavePool() public {
        assertEq(address(adapter.aavePool()), address(POOL));
        address POOL_PRIME = 0x4e033931ad43597d96D6bcc25c280717730B58B1;

        AaveDataTypes.ReserveDataLegacy memory oldRdUsdc = POOL.getReserveData(address(USDC));
        vm.mockCall(
            POOL_PRIME, abi.encodeWithSelector(IAavePool.getReserveData.selector, address(USDC)), abi.encode(oldRdUsdc)
        );

        AaveDataTypes.ReserveDataLegacy memory oldRdSusde = POOL.getReserveData(address(SUSDE));
        vm.mockCall(
            POOL_PRIME,
            abi.encodeWithSelector(IAavePool.getReserveData.selector, address(SUSDE)),
            abi.encode(oldRdSusde)
        );

        AaveDataTypes.ReserveDataLegacy memory oldRdPt = POOL.getReserveData(address(PT_SUSDE_SEP));
        vm.mockCall(
            POOL_PRIME,
            abi.encodeWithSelector(IAavePool.getReserveData.selector, address(PT_SUSDE_SEP)),
            abi.encode(oldRdPt)
        );

        // Update the aave pool (just point it to the prime market)
        {
            PoolAddressesProvider PAP = PoolAddressesProvider(POOL_ADDRESS_PROVIDER);
            vm.prank(PAP.owner());
            PAP.setAddress("POOL", POOL_PRIME);
            assertEq(PAP.getPool(), POOL_PRIME);
        }

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterAaveV3.AavePoolUpdated(POOL_PRIME);
        adapter.updateAavePool();

        assertEq(address(adapter.aavePool()), POOL_PRIME);

        assertEq(USDC.allowance(address(adapter), address(POOL)), 0);
        assertEq(SUSDE.allowance(address(adapter), address(POOL)), 0);
        assertEq(PT_SUSDE_SEP.allowance(address(adapter), address(POOL)), 0);

        assertEq(USDC.allowance(address(adapter), POOL_PRIME), type(uint256).max);
        assertEq(SUSDE.allowance(address(adapter), POOL_PRIME), type(uint256).max);
        assertEq(PT_SUSDE_SEP.allowance(address(adapter), POOL_PRIME), type(uint256).max);
    }

    function test_setReferralCode_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterAaveV3.ReferralCodeSet(123);
        adapter.setReferralCode(123);
        assertEq(adapter.referralCode(), 123);
    }

    function test_setUserUseReserveAsCollateral_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(UnderlyingBalanceZero.selector);
        adapter.setUserUseReserveAsCollateral(address(SUSDE), true);
    }

    function test_setUserUseReserveAsCollateral_success() public {
        uint256 amount = 500e18;
        supply(SUSDE, amount);

        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter.aavePool()));
        emit IAavePool.ReserveUsedAsCollateralDisabled(address(SUSDE), address(adapter));
        adapter.setUserUseReserveAsCollateral(address(SUSDE), false);

        vm.expectEmit(address(adapter.aavePool()));
        emit IAavePool.ReserveUsedAsCollateralEnabled(address(SUSDE), address(adapter));
        adapter.setUserUseReserveAsCollateral(address(SUSDE), true);
    }

    function test_setEModeCategory() public {
        uint256 amount = 500e18;
        supply(SUSDE, amount);
        supply(PT_SUSDE_SEP, amount);

        vm.startPrank(address(manager));
        adapter.borrow(400e6, alice);

        assertEq(adapter.aavePool().getUserEMode(address(adapter)), EMODE_PT_SUSDE_SEP_2025);
        assertEq(adapter.maxSafeLtv(), 0.9e18);
        assertEq(adapter.liquidationLtv(), 0.92e18);

        vm.startPrank(origamiMultisig);
        adapter.setEModeCategory(0);
        assertEq(adapter.currentLtv(), 0.365076496473374384e18);
        assertEq(adapter.maxSafeLtv(), 0.393e18); // the weighted avg
        assertEq(adapter.liquidationLtv(), 0.4096e18);
        assertEq(adapter.aavePool().getUserEMode(address(adapter)), 0);

        adapter.setEModeCategory(EMODE_PT_SUSDE_SEP_2025);
        assertEq(adapter.currentLtv(), 0.365076496473374384e18);
        assertEq(adapter.maxSafeLtv(), 0.9e18); // the weighted avg
        assertEq(adapter.liquidationLtv(), 0.92e18);

        // After an extra borrow, the currentLTV is higher than the emode=0 max safe LTV
        vm.startPrank(manager);
        adapter.borrow(35e6, alice);
        assertEq(adapter.currentLtv(), 0.397020690747690314e18);
        vm.startPrank(origamiMultisig);
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.397020690747690314e18, 0, 0.393e18)
        );
        adapter.setEModeCategory(0);

        // Do another extra borrow and the currentLTV is higher than the emode=0 liquidation LTV
        vm.startPrank(manager);
        adapter.borrow(15e6, alice);
        assertEq(adapter.currentLtv(), 0.410711059331213264e18);
        vm.startPrank(origamiMultisig);

        // After this borrow, can't set the e-mode down as the new LTV would be too low
        vm.expectRevert(HealthFactorLowerThanLiquidationThreshold.selector);
        adapter.setEModeCategory(0);
    }

    function test_positionDetailsWithSusdeCollateralNoEmode() public {
        vm.prank(origamiMultisig);
        adapter.setEModeCategory(0);

        uint256 amount = 100e18;
        supply(SUSDE, amount);
        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
        assertEq(details.totalCollateralBase, 119.53973299e8);
        assertEq(details.totalDebtBase, 0);
        assertEq(details.availableBorrowsBase, 86.06860775e8);
        assertEq(details.liquidationLtv, 0.75e18);
        assertEq(details.maxSafeLtv, 0.72e18);
        assertEq(details.healthFactor, type(uint256).max);
        assertEq(details.currentLtv, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
        assertEq(adapter.liquidationLtv(), details.liquidationLtv);
    }

    function test_positionDetailsWithPtSusdeCollateralNoEmode() public {
        vm.prank(origamiMultisig);
        adapter.setEModeCategory(0);

        uint256 amount = 100e18;
        supply(PT_SUSDE_SEP, amount);
        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();

        assertEq(details.totalCollateralBase, 99.575345e8);
        assertEq(details.totalDebtBase, 0);
        assertEq(details.availableBorrowsBase, 0.04978767e8);
        assertEq(details.liquidationLtv, 0.001e18);
        assertEq(details.maxSafeLtv, 0.0005e18);
        assertEq(details.healthFactor, type(uint256).max);
        assertEq(details.currentLtv, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
        assertEq(adapter.liquidationLtv(), details.liquidationLtv);
    }

    function test_positionDetailsWithMixedCollateralNoEmode() public {
        vm.prank(origamiMultisig);
        adapter.setEModeCategory(0);

        uint256 amount = 100e18;
        supply(SUSDE, amount);
        supply(PT_SUSDE_SEP, amount);
        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();

        assertEq(details.totalCollateralBase, 219.11507799e8);
        assertEq(details.totalDebtBase, 0);
        assertEq(details.availableBorrowsBase, 86.11222565e8);
        assertEq(details.liquidationLtv, 0.4096e18);
        assertEq(details.maxSafeLtv, 0.393e18);
        assertEq(details.healthFactor, type(uint256).max);
        assertEq(details.currentLtv, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
        assertEq(adapter.liquidationLtv(), details.liquidationLtv);
    }

    function test_balanceSheet_noDirectDonations() public {
        deal(address(SUSDE), address(adapter), 420.69e18);
        deal(address(USDC), address(adapter), 123e6);
        checkExpectedBs(0, 0, 0);
    }

    function test_balanceSheet_collateralDonationsAreCounted() public {
        vm.startPrank(alice);
        deal(address(SUSDE), alice, 100e18);
        SUSDE.approve(address(POOL), 100e18);
        POOL.supply(address(SUSDE), 100e18, address(adapter), 0);

        checkExpectedBs(100e18 - 1, 0, 0);
    }

    function test_setMaxLoanUtilizationRatioOnJoin_failure() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18 + 1);
    }

    function test_setMaxLoanUtilizationRatioOnJoin_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(adapter));
        emit IOpalAdapterAaveV3.MaxLoanUtilizationRatioOnJoinSet(1e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);
        assertEq(adapter.maxLoanUtilizationRatioOnJoin(), 1e18);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IOpalAdapterAaveV3).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOpalAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiBundlerPlugin).interfaceId));
        assertTrue(adapter.supportsInterface(type(IERC165).interfaceId));
        assertTrue(adapter.supportsInterface(type(IOrigamiElevatedAccess).interfaceId));
        assertFalse(adapter.supportsInterface(type(IERC20).interfaceId));
    }
}

contract OpalAdapterAaveV3TestAccess is OpalAdapterAaveV3TestBase {
    function test_access_updateAavePool() public {
        expectElevatedAccess();
        adapter.updateAavePool();
    }

    function test_access_setReferralCode() public {
        expectElevatedAccess();
        adapter.setReferralCode(123);
    }

    function test_access_setUserUseReserveAsCollateral() public {
        expectElevatedAccess();
        adapter.setUserUseReserveAsCollateral(alice, true);
    }

    function test_access_setEModeCategory() public {
        expectElevatedAccess();
        adapter.setEModeCategory(1);
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
        adapter.supplyCollateral(address(SUSDE), 0, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.supplyCollateral(address(SUSDE), 0, 0);
    }

    function test_access_withdrawCollateral() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.withdrawCollateral(address(SUSDE), 0, alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.withdrawCollateral(address(SUSDE), 0, alice);
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

    function test_access_claimAllRewards() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, alice));
        adapter.claimAllRewards(alice, mkArray(alice), alice);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiBundlerPlugin.InvalidBundler.selector, origamiMultisig));
        adapter.claimAllRewards(alice, mkArray(alice), alice);
    }
}

contract OpalAdapterAaveV3TestJoinExit is OpalAdapterAaveV3TestBase {
    error CollateralCannotCoverNewBorrow();

    function test_join_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18), mkArray(123e18), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.join(mkArray(123e18, 123e18), mkArray(123e18, 123e18), alice);
    }

    function test_join_fail_noAllowance() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: insufficient allowance");
        adapter.join(mkArray(123e18, 0), mkArray(0), alice);
    }

    function test_join_fail_noBalance() public {
        vm.startPrank(manager);
        SUSDE.approve(address(adapter), 123e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        adapter.join(mkArray(123e18, 0), mkArray(0), alice);
    }

    function test_join_success() public {
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 334_604_008.472810258951975566e18, 13_252_453.929449401238338332e18);
        expectArr(liabilities, 404_451_699.812534e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 965_395_991.527189741048026755e18, 2_386_747_546.070550598761661668e18);
        expectArr(liabilities, 4_980_935_936.924065e6);

        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt));
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt1 - 1, collateralAmt2, borrowAmt + 1);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.176898983263554083e18);
        assertEq(adapter.healthFactor(), 5.200708240529184436e18);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18);
        expectArr(liabilities, 404_451_599.812534e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18);
        expectArr(liabilities, 4_980_936_036.924066e6);
    }

    function test_join_someCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 0;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 0;
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Join(mkArray(collateralAmt1, collateralAmt2), mkArray(0));
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(0), alice);

        checkExpectedBs(collateralAmt1, collateralAmt2, borrowAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_join_zeroCollateral_zeroBorrow() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 0;
        uint256 collateralAmt2 = 0;
        uint256 borrowAmt = 0;

        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        checkExpectedBs(collateralAmt1, collateralAmt2, borrowAmt);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_join_zeroCollateral_someBorrow() public {
        vm.startPrank(manager);

        // Do an initial join first
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        {
            deal(address(SUSDE), address(manager), collateralAmt1);
            SUSDE.approve(address(adapter), collateralAmt1);
            deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
            PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
            vm.expectEmit(address(adapter));
            emit IOpalAdapter.Join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt));
            adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
        }

        collateralAmt1 = 0;
        collateralAmt2 = 0;
        borrowAmt = 1e18;
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overSafeLtv() public {
        vm.startPrank(manager);

        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        // max borrow
        // aave USDC/USD oracle price: 0.99575345e8
        // max USD borrow: 508.72528852 e8
        // USDC to borrow: (uint256(1e8) * 508.72528852e8 / 0.99992206e8) - 1
        uint256 borrowAmt = ((uint256(1e8) * 508.72528852e8 / 0.99992206e8) / 1e2) - 1;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
        assertEq(adapter.currentLtv(), 0.89999999884652874e18);
        assertEq(adapter.healthFactor(), 1.022222223532337729e18);
        assertEq(adapter.maxSafeLtv(), 0.9e18);
        assertEq(adapter.liquidationLtv(), 0.92e18);

        skip(30 days);
        assertEq(adapter.currentLtv(), 0.90154354001469394e18);
        assertEq(adapter.healthFactor(), 1.020472067255903408e18);

        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
        assertEq(details.totalCollateralBase, 567.01679624e8);
        assertEq(details.totalDebtBase, 511.19032973e8);
        assertEq(details.availableBorrowsBase, 0);
        assertEq(details.liquidationLtv, 0.92e18);
        assertEq(details.maxSafeLtv, 0.9e18);
        assertEq(details.healthFactor, 1.020472067255903409e18);
        assertEq(details.currentLtv, 0.90154354001469394e18);
        assertEq(adapter.currentLtv(), 0.90154354001469394e18);
        assertEq(adapter.maxSafeLtv(), details.maxSafeLtv);
        assertEq(adapter.liquidationLtv(), details.liquidationLtv);

        // Can't borrow the same again (with just a little less collateral)
        collateralAmt1 -= 1e18;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        vm.expectRevert(abi.encodeWithSelector(CollateralCannotCoverNewBorrow.selector));
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_withBorrow() public {
        vm.startPrank(origamiMultisig);
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.832408481174465776e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(0.8e18);

        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.832408497886354728e18, 0, 0.8e18)
        );
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
    }

    function test_join_fail_overUtilizationRatio_zeroBorrow() public {
        vm.startPrank(origamiMultisig);
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.832408481174465776e18);
        adapter.setMaxLoanUtilizationRatioOnJoin(0.8e18);

        vm.startPrank(manager);
        uint256 collateralAmt1 = 1e18;
        uint256 collateralAmt2 = 1e18;
        uint256 borrowAmt = 0;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
        checkExpectedBs(collateralAmt1 - 1, collateralAmt2, borrowAmt);
    }

    function test_join_fail_notEnoughCollateral() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        // max borrow
        // aave USDC/USD oracle price: 0.99575345e8
        // max USD borrow: 508.72528852 e8
        // USDC to borrow: (uint256(1e8) * 508.72528852e8 / 0.99992206e8) - 1
        uint256 maxBorrowAmt = ((uint256(1e8) * 508.72528852e8 / 0.99992206e8) / 1e2) - 1;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);

        vm.expectRevert(abi.encodeWithSelector(CollateralCannotCoverNewBorrow.selector));
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(maxBorrowAmt + 1), alice);
    }

    function test_exit_fail_wrongLength() public {
        vm.startPrank(manager);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18), mkArray(123e18), alice);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidLength.selector));
        adapter.exit(mkArray(123e18, 123e18), mkArray(123e18, 123e18), alice);
    }

    function test_exit_fail_notEnough() public {
        vm.startPrank(manager);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        adapter.exit(mkArray(0, 1), mkArray(123e18), alice);
    }

    function test_exit_success() public {
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        (uint256[] memory assets, uint256[] memory liabilities) = adapter.maxJoin();
        expectArr(assets, 334_604_008.472810258951975566e18, 13_252_453.929449401238338332e18);
        expectArr(liabilities, 404_451_699.812534e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 965_395_991.527189741048026755e18, 2_386_747_546.070550598761661668e18);
        expectArr(liabilities, 4_980_935_936.924065e6);

        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e6;
        uint256 withdrawAmt1 = 10e18;
        uint256 withdrawAmt2 = 20e18;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt1 - withdrawAmt1 - 2, collateralAmt2 - withdrawAmt2, borrowAmt - repayAmt + 2);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(SUSDE.balanceOf(alice), withdrawAmt1);
        assertEq(PT_SUSDE_SEP.balanceOf(alice), withdrawAmt2);
        assertEq(adapter.currentLtv(), 0.125603921150061256e18);
        assertEq(adapter.healthFactor(), 7.324612094720032739e18);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);

        (assets, liabilities) = adapter.maxJoin();
        expectArr(assets, 334_603_895.472810258951975567e18, 13_252_053.929449401238338332e18);
        expectArr(liabilities, 404_451_632.812534e6); //1_002_828_036.894379e6);
        (assets, liabilities) = adapter.maxExit();
        expectArr(assets, 965_396_104.527189741048026755e18, 2_386_747_946.070550598761661668e18);
        expectArr(liabilities, 4_980_936_003.924066e6);
    }

    function test_exit_zeroRepay_someWithdrawal() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 0;
        uint256 withdrawAmt1 = 20e18;
        uint256 withdrawAmt2 = 0;
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt1 - withdrawAmt1 - 2, collateralAmt2 - withdrawAmt2, borrowAmt - repayAmt + 1);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(SUSDE.balanceOf(alice), withdrawAmt1);
        assertEq(PT_SUSDE_SEP.balanceOf(alice), withdrawAmt2);
        assertEq(adapter.currentLtv(), 0.184711583290345256e18);
        assertEq(adapter.healthFactor(), 4.980737989527523855e18);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_exit_zeroRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        assertEq(adapter.currentLtv(), 0.176898983263554083e18);
        assertEq(adapter.healthFactor(), 5.200708240529184436e18);

        uint256 repayAmt = 0;
        uint256 withdrawAmt1 = 0;
        uint256 withdrawAmt2 = 0;
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);

        checkExpectedBs(collateralAmt1 - withdrawAmt1 - 1, collateralAmt2 - withdrawAmt2, borrowAmt - repayAmt + 1);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(SUSDE.balanceOf(alice), withdrawAmt1);
        assertEq(PT_SUSDE_SEP.balanceOf(alice), withdrawAmt2);
        assertEq(adapter.currentLtv(), 0.176898983263554083e18);
        assertEq(adapter.healthFactor(), 5.200708240529184436e18);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_exit_someRepay_zeroWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 33e6;
        uint256 withdrawAmt1 = 0;
        uint256 withdrawAmt2 = 0;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectRevert(abi.encodeWithSelector(IOpalAdapter.NoCollateral.selector));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);
    }

    function test_exit_repayTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 101e6;
        uint256 withdrawAmt1 = collateralAmt1 - 1;
        uint256 withdrawAmt2 = collateralAmt2;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);

        checkExpectedBs(0, 0, 0);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(USDC.balanceOf(address(adapter)), 1e6 - 1);
        assertEq(SUSDE.balanceOf(alice), withdrawAmt1);
        assertEq(PT_SUSDE_SEP.balanceOf(alice), withdrawAmt2);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_exit_maxWithdraw() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 100e6 + 1;
        uint256 withdrawAmt1 = type(uint256).max;
        uint256 withdrawAmt2 = collateralAmt2;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);

        // Note the event amount shows 'max'. Not realistic that the manager would send
        // through max anyway
        vm.expectEmit(address(adapter));
        emit IOpalAdapter.Exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);

        checkExpectedBs(0, 0, 0);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(USDC.balanceOf(manager), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(SUSDE.balanceOf(alice), collateralAmt1 - 1);
        assertEq(PT_SUSDE_SEP.balanceOf(alice), withdrawAmt2);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
        adapter.validateLtvInRange(0, AAVE_EMODE_MAX_BORROW_LTV);
    }

    function test_exit_withdrawTooMuch() public {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);

        uint256 repayAmt = 100e6;
        uint256 withdrawAmt1 = 10_000e18;
        uint256 withdrawAmt2 = collateralAmt2;
        deal(address(USDC), address(manager), repayAmt);
        USDC.approve(address(adapter), repayAmt);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughAvailableUserBalance.selector));
        adapter.exit(mkArray(withdrawAmt1, withdrawAmt2), mkArray(repayAmt), alice);
    }
}

contract MockAaveRewardsController is IAaveV3RewardsController {
    using SafeERC20 for IERC20;

    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts)
    {
        rewardsList = new address[](assets.length);
        claimedAmounts = new uint256[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            uint256 bal = IERC20(assets[i]).balanceOf(address(this));
            rewardsList[i] = assets[i];
            claimedAmounts[i] = bal;
            if (bal > 0) {
                IERC20(assets[i]).safeTransfer(to, bal);
            }
        }
    }
}

contract OpalAdapterAaveV3TestBundlerActions is OpalAdapterAaveV3TestBase {
    error InvalidAmount();
    error CollateralCannotCoverNewBorrow();

    function test_supplyCollateral_zeroAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt1 = 0;
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        adapter.supplyCollateral(address(SUSDE), collateralAmt1, 0);

        // No-op if under the min
        adapter.supplyCollateral(address(SUSDE), collateralAmt1, 1);
        checkExpectedBs(collateralAmt1, 0, 0);
    }

    function test_supplyCollateral_specifiedAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt1 = 123e18;
        deal(address(SUSDE), address(adapter), collateralAmt1 * 2);
        assertEq(adapter.supplyCollateral(address(SUSDE), collateralAmt1, 0), collateralAmt1);
        checkExpectedBs(collateralAmt1 - 1, 0, 0);
    }

    function test_supplyCollateral_maxOverMinAmount() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt1 = 123e18;
        deal(address(SUSDE), address(adapter), collateralAmt1);
        assertEq(adapter.supplyCollateral(address(SUSDE), type(uint256).max, collateralAmt1), collateralAmt1);
        checkExpectedBs(collateralAmt1 - 1, 0, 0);
    }

    function test_supplyCollateral_maxUnderMinAmount() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt1 = 123e18;
        deal(address(SUSDE), address(adapter), collateralAmt1);
        assertEq(adapter.supplyCollateral(address(SUSDE), type(uint256).max, collateralAmt1 + 1), 0);

        // No op
        checkExpectedBs(0, 0, 0);
    }

    function test_supplyCollateral_nonBSAsset() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt1 = 123e18;
        deal(address(USDE), address(adapter), collateralAmt1);
        vm.expectRevert("ERC20: insufficient allowance");
        adapter.supplyCollateral(address(USDE), type(uint256).max, 0);

        // As part of the bundle it can set the erc20 approval however.
        adapter.erc20Approve(address(USDE), address(POOL), collateralAmt1);
        assertEq(adapter.supplyCollateral(address(USDE), type(uint256).max, 0), collateralAmt1);
        checkExpectedBs(0, 0, 0);
    }

    function test_withdrawCollateral_zeroAmt() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 0;
        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        adapter.withdrawCollateral(address(SUSDE), collateralAmt, alice);
    }

    function test_withdrawCollateral_notEnough() public {
        vm.startPrank(address(manager));
        uint256 collateralAmt = 123e18;
        vm.expectRevert(abi.encodeWithSelector(NotEnoughAvailableUserBalance.selector));
        adapter.withdrawCollateral(address(SUSDE), collateralAmt, alice);
    }

    function test_withdrawCollateral_specifiedAmt() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        uint256 withdrawAmt = 123e18;
        assertEq(adapter.withdrawCollateral(address(SUSDE), withdrawAmt, alice), withdrawAmt);
        assertEq(SUSDE.balanceOf(alice), withdrawAmt);
        checkExpectedBs(supplyAmt - withdrawAmt - 1, 0, 0);
    }

    function test_withdrawCollateral_max() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        assertEq(adapter.withdrawCollateral(address(SUSDE), type(uint256).max, alice), supplyAmt - 1);
        assertEq(SUSDE.balanceOf(alice), supplyAmt - 1);
        checkExpectedBs(0, 0, 0);
    }

    function test_borrow_zeroAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        vm.expectRevert(abi.encodeWithSelector(InvalidAmount.selector));
        adapter.borrow(0, alice);
    }

    function test_borrow_notEnoughCollateral() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18; // 1 sUSDe == ~1.2 USD
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        uint256 borrowAmt = 1076e6;
        vm.expectRevert(abi.encodeWithSelector(CollateralCannotCoverNewBorrow.selector));
        adapter.borrow(borrowAmt, alice);
    }

    function test_borrow_success() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        uint256 borrowAmt = 780e6;
        adapter.borrow(borrowAmt, alice);
        assertEq(USDC.balanceOf(alice), borrowAmt);
        assertEq(adapter.currentLtv(), 0.652451856995970134e18);
        assertEq(adapter.healthFactor(), 1.410065723831149086e18);
    }

    function test_repay_tooManyAssets() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // Aave pays off as much as possible
        assertEq(adapter.repay(borrowAmt + 1e6, 0), borrowAmt + 1);
        assertEq(USDC.balanceOf(address(adapter)), 1e6 - 1);
        checkExpectedBs(supplyAmt - 1, 0, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_max_overMinAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // Aave pays off as much as possible
        assertEq(adapter.repay(type(uint256).max, borrowAmt + 1e6), borrowAmt + 1);
        assertEq(USDC.balanceOf(address(adapter)), 1e6 - 1);
        checkExpectedBs(supplyAmt - 1, 0, 0);
        assertEq(adapter.currentLtv(), 0);
        assertEq(adapter.healthFactor(), type(uint256).max);
    }

    function test_repay_max_underMinAmount() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        // An extra USDC to start
        deal(address(USDC), address(adapter), 1e6);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // Under threshold
        assertEq(adapter.repay(type(uint256).max, borrowAmt + 1e6 + 1), 0);
        assertEq(USDC.balanceOf(address(adapter)), borrowAmt + 1e6);
        checkExpectedBs(supplyAmt - 1, 0, borrowAmt + 1);
        assertEq(adapter.currentLtv(), 0.627357554835992127e18);
        assertEq(adapter.healthFactor(), 1.466468352709185681e18);
    }

    function test_repay_exact() public {
        vm.startPrank(address(manager));
        uint256 supplyAmt = 1000e18;
        deal(address(SUSDE), address(adapter), supplyAmt);
        adapter.supplyCollateral(address(SUSDE), supplyAmt, 0);

        uint256 borrowAmt = 750e6;
        adapter.borrow(borrowAmt, address(adapter));

        // A couple of gwei outstanding
        assertEq(adapter.repay(borrowAmt, borrowAmt), borrowAmt);
        assertEq(USDC.balanceOf(address(adapter)), 0);
        checkExpectedBs(supplyAmt - 1, 0, 2);
        assertEq(adapter.currentLtv(), 0.000000001673083878e18);
        assertEq(adapter.healthFactor(), 549_882_771.627544186998615021e18);
    }

    function test_claimAllRewards() public {
        MockAaveRewardsController rewardsController = new MockAaveRewardsController();
        MockERC20 REWARD1 = new MockERC20("REWARD1", "REWARD1", 18);
        MockERC20 REWARD2 = new MockERC20("REWARD2", "REWARD2", 6);
        MockERC20 REWARD3 = new MockERC20("REWARD3", "REWARD3", 18);
        deal(address(REWARD1), address(rewardsController), 33.33e18);
        deal(address(REWARD2), address(rewardsController), 99e6);
        deal(address(REWARD3), address(rewardsController), 50e18);

        vm.startPrank(manager);
        (address[] memory rewardsList, uint256[] memory claimedAmounts) =
            adapter.claimAllRewards(address(rewardsController), mkArray(address(REWARD2), address(REWARD3)), alice);
        expectArr(rewardsList, address(REWARD2), address(REWARD3));
        expectArr(claimedAmounts, 99e6, 50e18);
        assertEq(REWARD1.balanceOf(address(rewardsController)), 33.33e18);
        assertEq(REWARD1.balanceOf(alice), 0);
        assertEq(REWARD2.balanceOf(alice), 99e6);
        assertEq(REWARD3.balanceOf(alice), 50e18);
    }

    function test_validateLtvInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLtvInRange(0.82e18, 0.1e18);
    }

    function test_validateLtvInRange() public {
        vm.startPrank(manager);
        uint256 collateralAmt = 123e18;
        deal(address(SUSDE), address(adapter), collateralAmt * 2);
        adapter.supplyCollateral(address(SUSDE), collateralAmt, 0);

        uint256 borrowAmt = 123e6;
        adapter.borrow(borrowAmt, alice);
        assertEq(adapter.currentLtv(), 0.83647674551698015e18);

        // no-op
        adapter.validateLtvInRange(0.83e18, 0.84e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.83647674551698015e18, 0.82e18, 0.83e18)
        );
        adapter.validateLtvInRange(0.82e18, 0.83e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.83647674551698015e18, 0.84e18, 0.85e18)
        );
        adapter.validateLtvInRange(0.84e18, 0.85e18);

        // Bound by the max safe ltv within aave
        vm.startPrank(origamiMultisig);
        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
        vm.mockCall(
            address(POOL),
            abi.encodeWithSelector(IAavePool.getUserAccountData.selector),
            abi.encode(
                details.totalCollateralBase,
                details.totalDebtBase,
                details.availableBorrowsBase,
                details.liquidationLtv,
                7500, // 75%
                details.healthFactor
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(IOpalAdapter.LtvOutOfRange.selector, 0.83647674551698015e18, 0.1e18, 0.75e18)
        );
        adapter.validateLtvInRange(0.1e18, 0.85e18);
    }

    function test_validateLoanUtilizationRatioInRange_badParam() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        adapter.validateLoanUtilizationRatioInRange(0.82e18, 0.1e18);
    }

    function test_validateLoanUtilizationRatioInRange() public {
        assertEq(adapter.currentLoanTokenUtilizationRatio(), 0.832408481174465776e18);

        // no-op
        adapter.validateLoanUtilizationRatioInRange(0.83e18, 0.95e18);

        // above the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.832408481174465776e18, 0.81e18, 0.82e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.81e18, 0.82e18);

        // below the range
        vm.expectRevert(
            abi.encodeWithSelector(
                IOpalAdapter.UtilizationRatioOutOfRange.selector, 0.832408481174465776e18, 0.91e18, 0.93e18
            )
        );
        adapter.validateLoanUtilizationRatioInRange(0.91e18, 0.93e18);
    }
}

contract OpalAdapterAaveV3TestMaxJoinExit is OpalAdapterAaveV3TestBase {
    using AaveReserveConfiguration for AaveDataTypes.ReserveConfigurationMap;

    function checkFlags(
        address token,
        bool expectedActive,
        bool expectedFrozen,
        bool expectedBorrowingEnabled,
        bool expectedPaused
    ) internal view {
        AaveDataTypes.ReserveConfigurationMap memory config = POOL.getConfiguration(token);
        (bool active, bool frozen, bool borrowingEnabled, bool paused) = config.getFlags();
        assertEq(active, expectedActive);
        assertEq(frozen, expectedFrozen);
        assertEq(borrowingEnabled, expectedBorrowingEnabled);
        assertEq(paused, expectedPaused);
    }

    function expectMaxJoin(uint256 collateralAmt1, uint256 collateralAmt2, uint256 debtAmt) internal view {
        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxJoin();
        expectArr(assetAmounts, collateralAmt1, collateralAmt2);
        expectArr(liabilityAmounts, debtAmt);
    }

    function expectMaxExit(uint256 collateralAmt1, uint256 collateralAmt2, uint256 debtAmt) internal view {
        (uint256[] memory assetAmounts, uint256[] memory liabilityAmounts) = adapter.maxExit();
        expectArr(assetAmounts, collateralAmt1, collateralAmt2);
        expectArr(liabilityAmounts, debtAmt);
    }

    function doJoin() internal {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 100e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
        vm.stopPrank();
    }

    function test_maxJoin_default() public {
        checkFlags(address(SUSDE), true, false, false, false);
        checkFlags(address(PT_SUSDE_SEP), true, false, false, false);
        checkFlags(address(USDC), true, false, true, false);
        checkFlags(alice, false, false, false, false);

        expectMaxJoin(334_604_008.472810258951975566e18, 13_252_453.929449401238338332e18, 404_451_699.812534e6);
        doJoin();
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 404_451_599.812534e6);
        skip(1 days);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 404_371_336.776437e6);
    }

    function test_maxJoin_zeroFromFlags_asset() public {
        doJoin();
        address token = address(SUSDE);

        // !active
        setConfig(token, false, false, false, false, 1_300_000_000, 0);
        expectMaxJoin(0, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // frozen
        setConfig(token, true, true, false, false, 1_300_000_000, 0);
        expectMaxJoin(0, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // borrowable (no impact to supply)
        setConfig(token, true, false, true, false, 1_300_000_000, 0);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // paused
        setConfig(token, true, false, false, true, 1_300_000_000, 0);
        expectMaxJoin(0, 13_252_033.929449401238338332e18, 404_451_599.812534e6);
    }

    function test_maxJoin_zeroFromFlags_liability() public {
        doJoin();
        address token = address(USDC);

        // !active
        setConfig(token, false, false, true, false, 0, 7_000_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 0);

        // frozen
        setConfig(token, true, true, true, false, 0, 7_000_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 0);

        // !borrowable
        setConfig(token, true, false, false, false, 0, 7_000_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 0);

        // paused
        setConfig(token, true, false, true, true, 0, 7_000_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 0);
    }

    function test_maxJoin_supplyCaps_asset() public {
        doJoin();
        address token = address(SUSDE);

        // 2 billy
        setConfig(token, true, false, false, false, 2_000_000_000, 0);
        expectMaxJoin(1_034_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // unlilmited
        setConfig(token, true, false, false, false, 0, 0);
        expectMaxJoin(type(uint256).max, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // 100 milly (under current utilized)
        setConfig(token, true, false, false, false, 100_000_000, 0);
        expectMaxJoin(0, 13_252_033.929449401238338332e18, 404_451_599.812534e6);
    }

    function test_maxJoin_borrowCaps_liability() public {
        doJoin();
        address token = address(USDC);

        // unlilmited cap - uses available not yet borrowed
        setConfig(token, true, false, true, false, 0, 0);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 404_451_599.812534e6);

        // 5 billy cap and 4.98 billy utilized - uses amount left under cap
        setConfig(token, true, false, true, false, 0, 5_000_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 19_063_963.075934e6);

        // 100 milly (under current utilized)
        setConfig(token, true, false, true, false, 0, 100_000_000);
        expectMaxJoin(334_603_885.472810258951975567e18, 13_252_033.929449401238338332e18, 0);
    }

    function test_maxExit_default() public {
        expectMaxExit(965_395_991.527189741048026755e18, 2_386_747_546.070550598761661668e18, 4_980_935_936.924065e6);
        doJoin();
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);
        skip(1 days);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_981_738_667.28504e6);
    }

    function test_maxExit_zeroFromFlags_asset() public {
        doJoin();
        address token = address(SUSDE);

        // !active
        setConfig(token, false, false, false, false, 1_300_000_000, 0);
        expectMaxExit(0, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // frozen (no impact to withdraw)
        setConfig(token, true, true, false, false, 1_300_000_000, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // borrowable (no impact to withdraw)
        setConfig(token, true, false, true, false, 1_300_000_000, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // paused
        setConfig(token, true, false, false, true, 1_300_000_000, 0);
        expectMaxExit(0, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);
    }

    function test_maxExit_zeroFromFlags_liability() public {
        doJoin();
        address token = address(USDC);

        // !active
        setConfig(token, false, false, true, false, 0, 7_000_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 0);

        // frozen (no impact to repay)
        setConfig(token, true, true, true, false, 0, 7_000_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // !borrowable (no impact to repay)
        setConfig(token, true, false, false, false, 0, 7_000_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // paused
        setConfig(token, true, false, true, true, 0, 7_000_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 0);
    }

    function test_maxExit_supplyCaps_asset() public {
        doJoin();
        address token = address(SUSDE);

        // 2 billy (no impact to withdraw)
        setConfig(token, true, false, false, false, 2_000_000_000, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // unlilmited (no impact to withdraw)
        setConfig(token, true, false, false, false, 0, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // 100 milly (no impact to withdraw)
        setConfig(token, true, false, false, false, 100_000_000, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);
    }

    function test_maxExit_borrowCaps_liability() public {
        doJoin();
        address token = address(USDC);

        // unlilmited cap (no impact to withdraw)
        setConfig(token, true, false, true, false, 0, 0);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // 5 billy cap (no impact to withdraw)
        setConfig(token, true, false, true, false, 0, 5_000_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);

        // 100 milly (no impact to withdraw)
        setConfig(token, true, false, true, false, 0, 100_000_000);
        expectMaxExit(965_396_114.527189741048026755e18, 2_386_747_966.070550598761661668e18, 4_980_936_036.924066e6);
    }
}

contract OpalAdapterAaveV3TestViews is OpalAdapterAaveV3TestBase {
    function test_currentLtv_noDebt() public {
        uint256 amount = 500e18;
        supply(SUSDE, amount);
        assertEq(adapter.currentLtv(), 0);
    }

    function test_currentLtv_noCollateral() public {
        vm.startPrank(origamiMultisig);
        IOpalAdapterAaveV3.AavePositionDetails memory details = adapter.positionDetails();
        vm.mockCall(
            address(POOL),
            abi.encodeWithSelector(IAavePool.getUserAccountData.selector),
            abi.encode(
                0,
                1e18,
                details.availableBorrowsBase,
                details.liquidationLtv / 1e14,
                details.maxSafeLtv / 1e14,
                details.healthFactor
            )
        );
        assertEq(adapter.currentLtv(), type(uint256).max);
    }

    function _doJoin() private {
        vm.startPrank(manager);
        uint256 collateralAmt1 = 123e18;
        uint256 collateralAmt2 = 420e18;
        uint256 borrowAmt = 500e6;
        deal(address(SUSDE), address(manager), collateralAmt1);
        SUSDE.approve(address(adapter), collateralAmt1);
        deal(address(PT_SUSDE_SEP), address(manager), collateralAmt2);
        PT_SUSDE_SEP.approve(address(adapter), collateralAmt2);
        adapter.join(mkArray(collateralAmt1, collateralAmt2), mkArray(borrowAmt), alice);
        vm.stopPrank();
    }

    function test_currentLtv_multiAsset() public {
        _doJoin();

        assertEq(adapter.currentLtv(), 0.884494909241259612e18);
        assertEq(adapter.maxSafeLtv(), 0.9e18);
        assertEq(adapter.liquidationLtv(), 0.92e18);
    }

    function test_joinMetrics_supply() public {
        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 2);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 1_300_000_000e18);
            assertEq(supplyMetrics[0].alreadySupplied, 965_395_991.527189741048024434e18);
            assertFalse(supplyMetrics[1].supplyingDisabled);
            assertEq(supplyMetrics[1].aaveSupplyCap, 2_400_000_000e18);
            assertEq(supplyMetrics[1].alreadySupplied, 2_386_747_546.070550598761661668e18);
        }

        _doJoin();

        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertEq(supplyMetrics.length, 2);
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, 1_300_000_000e18);
            assertEq(supplyMetrics[0].alreadySupplied, 965_396_114.527189741048024433e18);
            assertFalse(supplyMetrics[1].supplyingDisabled);
            assertEq(supplyMetrics[1].aaveSupplyCap, 2_400_000_000e18);
            assertEq(supplyMetrics[1].alreadySupplied, 2_386_747_966.070550598761661668e18);
        }

        address token = address(SUSDE);

        // !active
        setConfig(token, false, false, false, false, 1_300_000_000, 0);
        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertTrue(supplyMetrics[0].supplyingDisabled);
            assertFalse(supplyMetrics[1].supplyingDisabled);
        }

        // frozen
        setConfig(token, true, true, false, false, 1_300_000_000, 0);
        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertTrue(supplyMetrics[0].supplyingDisabled);
            assertFalse(supplyMetrics[1].supplyingDisabled);
        }

        // paused
        setConfig(token, true, false, false, true, 1_300_000_000, 0);
        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertTrue(supplyMetrics[0].supplyingDisabled);
            assertFalse(supplyMetrics[1].supplyingDisabled);
        }

        // no supply cap
        setConfig(token, true, false, false, false, 0, 0);
        {
            (IOpalAdapterAaveV3.AssetSupplyMetrics[] memory supplyMetrics,) = adapter.joinMetrics();
            assertFalse(supplyMetrics[0].supplyingDisabled);
            assertFalse(supplyMetrics[1].supplyingDisabled);
            assertEq(supplyMetrics[0].aaveSupplyCap, type(uint256).max);
            assertEq(supplyMetrics[1].aaveSupplyCap, 2_400_000_000e18);
        }
    }

    function test_joinMetrics_borrow() public {
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 5_385_387_636.736599e6);
            assertEq(borrowMetrics.alreadyBorrowed, 4_980_935_936.924065e6);
            assertEq(borrowMetrics.availableSupply, 1_002_828_103.894379e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 0);
            assertEq(borrowMetrics.isolationModeTotalDebt, 0);
        }

        _doJoin();

        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, 7_000_000_000e6);
            assertEq(borrowMetrics.joinBorrowCap, 5_385_387_636.736599e6);
            assertEq(borrowMetrics.alreadyBorrowed, 4_980_936_436.924065e6);
            assertEq(borrowMetrics.availableSupply, 1_002_827_603.894379e6);
            assertEq(borrowMetrics.isolationModeDebtCeiling, 0);
            assertEq(borrowMetrics.isolationModeTotalDebt, 0);
        }

        address token = address(USDC);

        // !active
        setConfig(token, false, false, true, false, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertTrue(borrowMetrics.borrowingDisabled);
        }

        // frozen
        setConfig(token, true, true, true, false, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertTrue(borrowMetrics.borrowingDisabled);
        }

        // !borrowable
        setConfig(token, true, false, false, false, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertTrue(borrowMetrics.borrowingDisabled);
        }

        // paused
        setConfig(token, true, false, true, true, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertTrue(borrowMetrics.borrowingDisabled);
        }

        // no borrow cap
        setConfig(token, true, false, true, false, 0, 0);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, type(uint256).max);
        }

        // No max UR
        vm.startPrank(origamiMultisig);
        adapter.setMaxLoanUtilizationRatioOnJoin(1e18);
        {
            (, IOpalAdapterAaveV3.LiabilityBorrowMetrics memory borrowMetrics) = adapter.joinMetrics();
            assertFalse(borrowMetrics.borrowingDisabled);
            assertEq(borrowMetrics.aaveBorrowCap, type(uint256).max);
            assertEq(borrowMetrics.joinBorrowCap, type(uint256).max);
        }
    }

    function test_exitMetrics_withdraw() public {
        {
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 2);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 965_395_991.527189741048026755e18);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
            assertEq(withdrawMetrics[1].availableSupply, 2_386_747_546.070550598761661668e18);
        }

        _doJoin();

        {
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertEq(withdrawMetrics.length, 2);
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 965_396_114.527189741048026755e18);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
            assertEq(withdrawMetrics[1].availableSupply, 2_386_747_966.070550598761661668e18);
        }

        address token = address(SUSDE);

        // !active
        setConfig(token, false, false, false, false, 1_300_000_000, 0);
        {
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertTrue(withdrawMetrics[0].withdrawingDisabled);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
        }

        // frozen
        setConfig(token, true, true, false, false, 1_300_000_000, 0);
        {
            // frozen doesn't affect withdrawals
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
        }

        // paused
        setConfig(token, true, false, false, true, 1_300_000_000, 0);
        {
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertTrue(withdrawMetrics[0].withdrawingDisabled);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
        }

        // no supply cap
        setConfig(token, true, false, false, false, 0, 0);
        {
            // no impact
            (IOpalAdapterAaveV3.AssetWithdrawMetrics[] memory withdrawMetrics,) = adapter.exitMetrics();
            assertFalse(withdrawMetrics[0].withdrawingDisabled);
            assertFalse(withdrawMetrics[1].withdrawingDisabled);
            assertEq(withdrawMetrics[0].availableSupply, 965_396_114.527189741048026755e18);
            assertEq(withdrawMetrics[1].availableSupply, 2_386_747_966.070550598761661668e18);
        }
    }

    function test_exitMetrics_repay() public {
        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 4_980_935_936.924065e6);
        }

        _doJoin();

        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 4_980_936_436.924065e6);
        }

        address token = address(USDC);

        // !active
        setConfig(token, false, false, true, false, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertTrue(repayMetrics.repayingDisabled);
        }

        // frozen
        setConfig(token, true, true, true, false, 0, 7_000_000_000);
        {
            // frozen doesn't affect repaying
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertFalse(repayMetrics.repayingDisabled);
        }

        // !borrowable
        setConfig(token, true, false, false, false, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertFalse(repayMetrics.repayingDisabled);
        }

        // paused
        setConfig(token, true, false, true, true, 0, 7_000_000_000);
        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertTrue(repayMetrics.repayingDisabled);
        }

        // no borrow cap
        setConfig(token, true, false, true, false, 0, 0);
        {
            (, IOpalAdapterAaveV3.LiabilityRepayMetrics memory repayMetrics) = adapter.exitMetrics();
            assertFalse(repayMetrics.repayingDisabled);
            assertEq(repayMetrics.alreadyBorrowed, 4_980_936_436.924065e6);
        }
    }
}
