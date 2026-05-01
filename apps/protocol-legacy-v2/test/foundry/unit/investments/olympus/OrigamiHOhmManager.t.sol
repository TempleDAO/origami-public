pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { OrigamiHOhmVault } from "contracts/investments/olympus/OrigamiHOhmVault.sol";
import { OrigamiSwapperWithCallback } from "contracts/common/swappers/OrigamiSwapperWithCallback.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

import { MockOhm } from "contracts/test/external/olympus/test/mocks/MockOhm.sol";
import { MockGohm } from "contracts/test/external/olympus/test/mocks/MockGohm.sol";
import { DLGTEv1 as IDLGTEv1 } from "contracts/test/external/olympus/src/modules/DLGTE/DLGTE.v1.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { Kernel, Actions } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import { DelegateEscrowFactory } from "contracts/test/external/olympus/src/external/cooler/DelegateEscrowFactory.sol";
import { CoolerLtvOracle } from "contracts/test/external/olympus/src/policies/cooler/CoolerLtvOracle.sol";
import { MockERC20 } from "contracts/test/external/olympus/test/mocks/MockERC20.sol";
import { IMonoCooler } from "contracts/test/external/olympus/src/policies/interfaces/cooler/IMonoCooler.sol";

import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { MockCoolerTreasuryBorrower } from "test/foundry/mocks/external/olympus/MockCoolerTreasuryBorrower.m.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { MockSUsdsToken } from "contracts/test/external/maker/MockSUsdsToken.m.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";

contract OrigamiHOhmManagerTestBase is OrigamiTest {
    using OrigamiMath for uint256;

    OrigamiHOhmManager internal manager;
    OrigamiHOhmVault internal vault;
    OrigamiSwapperWithCallback internal sweepSwapper;
    DummyDexRouter internal dexRouter;

    MockERC20 internal USDS;
    MockSUsdsToken internal sUSDS;
    MockOhm internal OHM;
    MockGohm internal gOHM;

    MockERC20 internal USDC;

    MonoCooler internal cooler;
    Kernel internal kernel;
    DelegateEscrowFactory internal escrowFactory;
    MockCoolerTreasuryBorrower internal treasuryBorrower;
    CoolerLtvOracle internal ltvOracle;
    IDLGTEv1 internal DLGTE;

    uint16 internal constant PERFORMANCE_FEE = 330; // 3.3%
    uint256 internal constant OHM_PER_GOHM = 269.24e18;
    uint40 internal constant DEFAULT_SWEEP_COOLDOWN = 1 days;
    uint96 internal constant DEFAULT_SWEEP_MAX_SELL = 1_000e18;

    address internal immutable OTHERS = makeAddr("OTHERS");

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    function setUp() public virtual {
        vm.warp(1_739_000_000);
        OlympusMonoCoolerDeployerLib.Contracts memory coolerContracts;
        OlympusMonoCoolerDeployerLib.deploy(coolerContracts, bytes32(0), origamiMultisig, OTHERS);

        USDS = coolerContracts.USDS;
        sUSDS = coolerContracts.sUSDS;
        OHM = coolerContracts.OHM;
        gOHM = coolerContracts.gOHM;
        cooler = coolerContracts.monoCooler;
        kernel = coolerContracts.kernel;
        escrowFactory = coolerContracts.escrowFactory;
        treasuryBorrower = MockCoolerTreasuryBorrower(address(coolerContracts.treasuryBorrower));
        ltvOracle = coolerContracts.ltvOracle;
        DLGTE = coolerContracts.DLGTE;

        vm.prank(origamiMultisig);
        ltvOracle.setOriginationLtvAt(uint96(uint256(11.5e18) * OHM_PER_GOHM / 1e18), uint32(vm.getBlockTimestamp()) + 182.5 days);

        deployVault();

        USDC = new MockERC20("USDC", "USDC", 6);
    }

    function deployVault() internal {
        vault = new OrigamiHOhmVault(
            origamiMultisig, 
            "Origami hOHM", 
            "hOHM",
            address(gOHM),
            address(0)
        );

        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        sweepSwapper = new OrigamiSwapperWithCallback(origamiMultisig);

        // A dummy dex aggregator router, and load up with hHOM that can be bought and burned
        dexRouter = new DummyDexRouter();
        deal(address(vault), address(dexRouter), 1_000_000e18, true);

        vm.startPrank(origamiMultisig);
        manager.setSweepParams(DEFAULT_SWEEP_COOLDOWN, DEFAULT_SWEEP_MAX_SELL);
        manager.setSweepSwapper(address(sweepSwapper));
        vault.setManager(address(manager));
        setExplicitAccess(sweepSwapper, address(manager), IOrigamiSwapper.execute.selector, true);
        sweepSwapper.whitelistRouter(address(dexRouter), true);
        vm.stopPrank();
    }

    function check_accountDelegationBalances(
        address account,
        uint256 shares,
        uint256 totalSupply,
        uint256 expectedTotalCollateral,
        address expectedDelegate,
        uint256 expectedDelegatedCollateral
    ) internal view {
        (
            uint256 totalCollateral,
            address delegateAddress,
            uint256 delegatedCollateral
        ) = manager.accountDelegationBalances(account, shares, totalSupply);
        assertEq(totalCollateral, expectedTotalCollateral, "accountDelegationBalances::totalCollateral");
        assertEq(delegateAddress, expectedDelegate, "accountDelegationBalances::delegateAddress");
        assertEq(delegatedCollateral, expectedDelegatedCollateral, "accountDelegationBalances::delegatedCollateral");
    }

    function check_dlgteSummary(
        uint256 expectedTotalGohm,
        uint256 expectedDelegatedGohm,
        uint256 expectedNumAddresses,
        uint256 epectedMaxAddresses
    ) internal view {
        (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        ) = DLGTE.accountDelegationSummary(address(manager));
        assertEq(totalGOhm, expectedTotalGohm, "DLGTE.accountDelegationSummary::totalGOhm");
        assertEq(delegatedGOhm, expectedDelegatedGohm, "DLGTE.accountDelegationSummary::delegatedGOhm");
        assertEq(numDelegateAddresses, expectedNumAddresses, "DLGTE.accountDelegationSummary::numDelegateAddresses");
        assertEq(maxAllowedDelegateAddresses, epectedMaxAddresses, "DLGTE.accountDelegationSummary::maxAllowedDelegateAddresses");
    }
}

contract OrigamiHOhmManagerTestAdmin is OrigamiHOhmManagerTestBase {
    event ExitFeeBpsSet(uint256 feeBps);
    event CoolerSet(address indexed cooler);
    event SavingsVaultSet(address indexed savingsVault);
    event SwapperSet(address indexed newSwapper);
    event SweepParamsSet(uint40 newSweepCooldownSecs, uint96 newMaxSweepSellAmount);
    event DebtTokenSet(address indexed debtToken, address indexed savingsVault);
    event CoolerBorrowsDisabledSet(bool value);
    event PerformanceFeeSet(uint256 fee);
    event FeeCollectorSet(address indexed feeCollector);

    function test_initialization() public {
        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );

        assertEq(manager.owner(), origamiMultisig);
        assertEq(manager.vault(), address(vault));
        assertEq(address(manager.cooler()), address(cooler));
        assertEq(address(manager.collateralToken()), address(gOHM));
        assertEq(address(manager.debtToken()), address(USDS));
        assertEq(address(manager.debtTokenSavingsVault()), address(sUSDS));
        assertEq(manager.debtTokenDecimalsToWadScalar(), 1);
        assertEq(manager.exitFeeBps(), 0);
        assertEq(manager.coolerBorrowsDisabled(), false);
        assertEq(address(manager.sweepSwapper()), address(0));
        assertEq(manager.sweepCooldownSecs(), 0);
        assertEq(manager.lastSweepTime(), 0);
        assertEq(manager.maxSweepSellAmount(), 0);
        assertEq(manager.MAX_EXIT_FEE_BPS(), 330);

        assertEq(gOHM.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), type(uint256).max);
        
        assertEq(manager.areJoinsPaused(), false);
        assertEq(manager.areExitsPaused(), false);
        assertEq(manager.debtTokenBalance(), 0);
        assertEq(manager.coolerDebtInWad(), 0);
        assertEq(manager.surplusDebtTokenAmount(), 0);
        assertEq(manager.collateralTokenBalance(), 0);

        assertEq(manager.performanceFeeBps(), PERFORMANCE_FEE);
        assertEq(manager.MAX_PERFORMANCE_FEE_BPS(), 330);
        assertEq(address(manager.feeCollector()), feeCollector);
    }

    function test_constructor_fail_decimals() public {
        vm.mockCall(
            address(USDS),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(19)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDS)));
        new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            PERFORMANCE_FEE,
            feeCollector
        );
    }

    function test_constructor_fail_feeBps() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(sUSDS),
            331,
            feeCollector
        );
    }

    function test_constructor_fail_badSavings() public {
        MockSUsdsToken badSavings = new MockSUsdsToken(USDC);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badSavings)));
        new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(badSavings),
            PERFORMANCE_FEE,
            feeCollector
        );
    }

    function test_constructor_noSavings() public {
        vm.mockCall(
            address(cooler),
            abi.encodeWithSelector(IMonoCooler.debtToken.selector),
            abi.encode(address(USDC))
        );
        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(0),
            PERFORMANCE_FEE,
            feeCollector
        );

        assertEq(address(manager.debtToken()), address(USDC));
        assertEq(address(manager.debtTokenSavingsVault()), address(0));
        assertEq(manager.debtTokenDecimalsToWadScalar(), 1e12);

        assertEq(gOHM.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(cooler)), 0);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
        assertEq(USDC.allowance(address(manager), address(cooler)), type(uint256).max);
    }

    function test_setExitFees_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setExitFees(331);
    }

    function test_setExitFees_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit ExitFeeBpsSet(123);
        manager.setExitFees(123);
        assertEq(manager.exitFeeBps(), 123);
    }

    function test_setCoolerBorrowsDisabled() public {
        vm.startPrank(origamiMultisig);
        assertEq(manager.coolerBorrowsDisabled(), false);
        vm.expectEmit(address(manager));
        emit CoolerBorrowsDisabledSet(true);
        manager.setCoolerBorrowsDisabled(true);
        assertEq(manager.coolerBorrowsDisabled(), true);
    }

    function test_setSweepParams() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit SweepParamsSet(3600, 123e18);
        manager.setSweepParams(3600, 123e18);
        assertEq(manager.sweepCooldownSecs(), 3600);
        assertEq(manager.maxSweepSellAmount(), 123e18);
    }

    function test_setSweepSwapper_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setSweepSwapper(address(0));
    }

    function test_setSweepSwapper_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit SwapperSet(alice);
        manager.setSweepSwapper(alice);
        assertEq(address(manager.sweepSwapper()), alice);
    }

    function test_setPerformanceFeesBps_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.setPerformanceFeesBps(331);
    }

    function test_setPerformanceFeesBps_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit PerformanceFeeSet(20);
        manager.setPerformanceFeesBps(20);
        assertEq(manager.performanceFeeBps(), 20);
    }

    function test_setFeeCollector_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        manager.setFeeCollector(address(0));
    }

    function test_setFeeCollector_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(manager));
        emit FeeCollectorSet(alice);
        manager.setFeeCollector(alice);
        assertEq(address(manager.feeCollector()), alice);
    }

    function test_setDebtTokenFromCooler_fail_notPaused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);

        manager.setPaused(IOrigamiManagerPausable.Paused(false, false));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.IsNotPaused.selector));
        manager.setDebtTokenFromCooler(address(0));

        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.IsNotPaused.selector));
        manager.setDebtTokenFromCooler(address(0));

        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.IsNotPaused.selector));
        manager.setDebtTokenFromCooler(address(0));
    }

    function test_setDebtTokenFromCooler_noChange() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        vm.expectEmit(address(manager));
        emit DebtTokenSet(address(USDS), address(sUSDS));
        manager.setDebtTokenFromCooler(address(sUSDS));
        assertEq(address(manager.debtToken()), address(USDS));
        assertEq(address(manager.debtTokenSavingsVault()), address(sUSDS));
        assertEq(USDS.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), type(uint256).max);
    }

    function test_setDebtTokenFromCooler_fail_badSavings() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        MockSUsdsToken badSavings = new MockSUsdsToken(USDC);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(badSavings)));
        manager.setDebtTokenFromCooler(address(badSavings));
    }

    function test_setDebtTokenFromCooler_fromUnsetSavings() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        manager.setDebtTokenFromCooler(address(0));
        
        MockSUsdsToken newSavings = new MockSUsdsToken(USDS);

        vm.expectEmit(address(manager));
        emit DebtTokenSet(address(USDS), address(newSavings));
        manager.setDebtTokenFromCooler(address(newSavings));

        assertEq(address(manager.debtToken()), address(USDS));
        assertEq(address(manager.debtTokenSavingsVault()), address(newSavings));
        assertEq(USDS.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
        assertEq(USDS.allowance(address(manager), address(newSavings)), type(uint256).max);
    }

    function test_setDebtTokenFromCooler_unsetSavings() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        vm.expectEmit(address(manager));
        emit DebtTokenSet(address(USDS), address(0));
        manager.setDebtTokenFromCooler(address(0));
        
        assertEq(address(manager.debtToken()), address(USDS));
        assertEq(address(manager.debtTokenSavingsVault()), address(0));
        assertEq(USDS.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
    }

    function test_setDebtTokenFromCooler_changeDebtToken_noSavings() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        MockCoolerTreasuryBorrower newTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(USDC));
        kernel.executeAction(Actions.ActivatePolicy, address(newTreasuryBorrower));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));

        vm.expectEmit(address(manager));
        emit DebtTokenSet(address(USDC), address(0));
        manager.setDebtTokenFromCooler(address(0));
        assertEq(address(manager.debtToken()), address(USDC));
        assertEq(address(manager.debtTokenSavingsVault()), address(0));
        assertEq(USDS.allowance(address(manager), address(cooler)), 0);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
        assertEq(USDC.allowance(address(manager), address(cooler)), type(uint256).max);
    }

    function test_setDebtTokenFromCooler_changeDebtToken_withSavings() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        MockCoolerTreasuryBorrower newTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(USDC));
        kernel.executeAction(Actions.ActivatePolicy, address(newTreasuryBorrower));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));

        MockSUsdsToken newSavings = new MockSUsdsToken(USDC);
        newSavings.setInterestRate(0.1e18);

        vm.expectEmit(address(manager));
        emit DebtTokenSet(address(USDC), address(newSavings));
        manager.setDebtTokenFromCooler(address(newSavings));
        assertEq(address(manager.debtToken()), address(USDC));
        assertEq(address(manager.debtTokenSavingsVault()), address(newSavings));
        assertEq(USDS.allowance(address(manager), address(cooler)), 0);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
        assertEq(USDC.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDC.allowance(address(manager), address(newSavings)), type(uint256).max);
    }

    function test_recoverToken_success() public {
        check_recoverToken(address(manager));
    }

    function test_recoverToken_fail() public {
        vm.startPrank(origamiMultisig);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDS)));
        manager.recoverToken(address(USDS), alice, 123);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(sUSDS)));
        manager.recoverToken(address(sUSDS), alice, 123);
    }
}

contract OrigamiHOhmManagerTestAccess is OrigamiHOhmManagerTestBase {
    function test_setExitFees_access() public {
        expectElevatedAccess();
        manager.setExitFees(123);
    }

    function test_setCoolerBorrowsDisabled_access() public {
        expectElevatedAccess();
        manager.setCoolerBorrowsDisabled(true);
    }

    function test_setSweepParams_access() public {
        expectElevatedAccess();
        manager.setSweepParams(123, 123);
    }
    
    function test_setSweepSwapper_access() public {
        expectElevatedAccess();
        manager.setSweepSwapper(alice);
    }
    
    function test_setPerformanceFeesBps_access() public {
        expectElevatedAccess();
        manager.setPerformanceFeesBps(123);
    }

    function test_setFeeCollector_access() public {
        expectElevatedAccess();
        manager.setFeeCollector(alice);
    }

    function test_setDebtTokenFromCooler_access() public {
        expectElevatedAccess();
        manager.setDebtTokenFromCooler(alice);
    }
    
    function test_recoverToken_access() public {
        expectElevatedAccess();
        manager.recoverToken(alice, alice, 123);
    }
    
    function test_syncDebtTokenSavings_access() public {
        expectElevatedAccess();
        manager.syncDebtTokenSavings(123);
    }
    
    function test_sweep_access() public {
        expectElevatedAccess();
        manager.sweep(123, bytes(""));
    }
    
    function test_join_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.join(123, 123, alice, 1, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.join(123, 123, alice, 1, 0);
    }
    
    function test_exit_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.exit(123, 123, alice, alice, 1, 0);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.exit(123, 123, alice, alice, 1, 0);
    }
    
    function test_updateDelegateAndAmount_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.updateDelegateAndAmount(alice, 123, 123, alice);
        
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.updateDelegateAndAmount(alice, 123, 123, alice);
    }
    
    function test_setDelegationAmount1_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.setDelegationAmount1(alice, 123, 123);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.setDelegationAmount1(alice, 123, 123);
    }
    
    function test_setDelegationAmount2_access() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.setDelegationAmount2(alice, 123, alice, 123, 123);

        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        manager.setDelegationAmount2(alice, 123, alice, 123, 123);
    }
}

contract OrigamiHOhmManagerTestSavings is OrigamiHOhmManagerTestBase {
    function test_syncDebtTokenSavings_savingsNotSet() public {
        manager = new OrigamiHOhmManager(
            origamiMultisig, 
            address(vault),
            address(cooler),
            address(0),
            PERFORMANCE_FEE,
            feeCollector
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 100e18);
        manager.syncDebtTokenSavings(1e18);
        assertEq(USDS.balanceOf(address(manager)), 100e18);
    }

    function test_syncDebtTokenSavings_depositNoCap() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 100e18);

        skip(365 days);
        manager.syncDebtTokenSavings(33e18);
        assertEq(USDS.balanceOf(address(manager)), 33e18);
        assertEq(sUSDS.balanceOf(address(manager)), 60.909090909090909090e18);

        assertEq(manager.surplusDebtTokenAmount(), 100e18 - 1);
    }

    function test_syncDebtTokenSavings_deposit_zeroMaxDeposit() public {
        vm.mockCall(
            address(sUSDS),
            abi.encodeWithSelector(IERC4626.maxDeposit.selector, address(manager)),
            abi.encode(0)
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 100e18);

        skip(365 days);
        manager.syncDebtTokenSavings(33e18);
        assertEq(USDS.balanceOf(address(manager)), 100e18);
        assertEq(sUSDS.balanceOf(address(manager)), 0);

        assertEq(manager.surplusDebtTokenAmount(), 100e18);
    }

    function test_syncDebtTokenSavings_deposit_smallMaxDeposit() public {
        vm.mockCall(
            address(sUSDS),
            abi.encodeWithSelector(IERC4626.maxDeposit.selector, address(manager)),
            abi.encode(1e18)
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 100e18);

        skip(365 days);
        manager.syncDebtTokenSavings(33e18);
        assertEq(USDS.balanceOf(address(manager)), 100e18 - 1e18);
        assertEq(sUSDS.balanceOf(address(manager)), 0.909090909090909090e18);

        assertEq(manager.surplusDebtTokenAmount(), 100e18 - 1);
    }

    function test_syncDebtTokenSavings_withdraw_noCap() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 33e18);
        deal(address(sUSDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 133e18);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
        manager.syncDebtTokenSavings(133e18);
        assertEq(USDS.balanceOf(address(manager)), 133e18);
        assertEq(sUSDS.balanceOf(address(manager)), 9.090909090909090909e18);

        assertEq(manager.surplusDebtTokenAmount(), 143e18 - 1);
    }

    function test_syncDebtTokenSavings_withdraw_zeroMaxWithdraw() public {
        vm.mockCall(
            address(sUSDS),
            abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(manager)),
            abi.encode(0)
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 33e18);
        deal(address(sUSDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 133e18);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
        manager.syncDebtTokenSavings(133e18);

        assertEq(USDS.balanceOf(address(manager)), 33e18);
        assertEq(sUSDS.balanceOf(address(manager)), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
    }

    function test_syncDebtTokenSavings_withdraw_smallMaxWithdraw() public {
        vm.mockCall(
            address(sUSDS),
            abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(manager)),
            abi.encode(1e18)
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 33e18);
        deal(address(sUSDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 133e18);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
        manager.syncDebtTokenSavings(133e18);

        assertEq(USDS.balanceOf(address(manager)), 34e18);
        assertEq(sUSDS.balanceOf(address(manager)), 99.090909090909090909e18);
        assertEq(manager.surplusDebtTokenAmount(), 143e18 - 1);
    }

    function test_syncDebtTokenSavings_noDifference() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDS), address(manager), 33e18);
        deal(address(sUSDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 133e18);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
        manager.syncDebtTokenSavings(33e18);
        
        assertEq(USDS.balanceOf(address(manager)), 33e18);
        assertEq(sUSDS.balanceOf(address(manager)), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 143e18);
    }
}

contract OrigamiHOhmManagerTestSweep is OrigamiHOhmManagerTestBase {
    event SweepStarted(address indexed debtToken, uint256 debtTokenAmount);
    event SweepFinished(uint256 hohmBurned, uint256 feeAmount);

    function test_sweep_fail_tooMuch() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.SweepTooLarge.selector));
        manager.sweep(DEFAULT_SWEEP_MAX_SELL + 1, bytes(""));

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.sweep(DEFAULT_SWEEP_MAX_SELL, bytes(""));
    }

    function test_sweep_fail_cooldown() public {
        vm.startPrank(origamiMultisig);

        deal(address(sUSDS), address(manager), 100e18);
        bytes memory encodedRouteData = abi.encode(
            IOrigamiSwapper.RouteDataWithCallback({
                router: address(dexRouter),
                minBuyAmount: 0,
                receiver: address(manager),
                data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(sUSDS), 33e18, address(vault), 10e18))
            })
        );
        manager.sweep(33e18, encodedRouteData);
        assertEq(manager.lastSweepTime(), uint128(vm.getBlockTimestamp()));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.BeforeCooldownEnd.selector));
        manager.sweep(33e18, encodedRouteData);

        skip(DEFAULT_SWEEP_COOLDOWN-1);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.BeforeCooldownEnd.selector));
        manager.sweep(33e18, encodedRouteData);

        skip(1);
        manager.sweep(33e18, encodedRouteData);
        assertEq(manager.lastSweepTime(), uint128(vm.getBlockTimestamp()));
    }

    function test_sweep_withSavingsVault() public {
        vm.startPrank(origamiMultisig);

        uint128 currentTimestamp = uint128(vm.getBlockTimestamp());
        skip(30 days);

        deal(address(sUSDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 100.821917808219178082e18);

        bytes memory encodedRouteData = abi.encode(
            IOrigamiSwapper.RouteDataWithCallback({
                router: address(dexRouter),
                minBuyAmount: 0,
                receiver: address(manager),
                data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(sUSDS), 33e18, address(vault), 10e18))
            })
        );

        assertEq(vault.totalSupply(), 1_000_000e18);
        vm.expectEmit(address(manager));
        emit SweepStarted(address(sUSDS), 33e18);
        vm.expectEmit(address(manager));
        emit SweepFinished(9.67e18, 0.33e18);
        manager.sweep(33e18, encodedRouteData);
        assertEq(vault.totalSupply(), 1_000_000e18 - 9.67e18);
        assertEq(vault.balanceOf(feeCollector), 0.33e18);
        assertEq(sUSDS.balanceOf(address(manager)), 67e18);
        assertEq(manager.surplusDebtTokenAmount(), 67.550684931506849315e18);
        assertEq(manager.lastSweepTime(), currentTimestamp + uint128(30 days));
    }

    function test_sweep_noSavingsVault() public {
        vm.startPrank(origamiMultisig);
        {
            manager.setPauser(address(origamiMultisig), true);
            manager.setPaused(IOrigamiManagerPausable.Paused(true, true));
            manager.setDebtTokenFromCooler(address(0));
        }

        uint128 currentTimestamp = uint128(vm.getBlockTimestamp());
        skip(30 days);

        deal(address(USDS), address(manager), 100e18);
        assertEq(manager.surplusDebtTokenAmount(), 100e18);

        bytes memory encodedRouteData = abi.encode(
            IOrigamiSwapper.RouteDataWithCallback({
                router: address(dexRouter),
                minBuyAmount: 0,
                receiver: address(manager),
                data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(USDS), 33e18, address(vault), 10e18))
            })
        );

        assertEq(vault.totalSupply(), 1_000_000e18);
        vm.expectEmit(address(manager));
        emit SweepStarted(address(USDS), 33e18);
        vm.expectEmit(address(manager));
        emit SweepFinished(9.67e18, 0.33e18);
        manager.sweep(33e18, encodedRouteData);
        assertEq(vault.totalSupply(), 1_000_000e18 - 9.67e18);
        assertEq(vault.balanceOf(feeCollector), 0.33e18);
        assertEq(USDS.balanceOf(address(manager)), 67e18);
        assertEq(manager.surplusDebtTokenAmount(), 67e18);
        assertEq(manager.lastSweepTime(), currentTimestamp + uint128(30 days));
    }

    function test_sweepCallback_noBalance() public {
        uint256 supplyBefore = vault.totalSupply();
        vm.expectEmit(address(manager));
        emit SweepFinished(0, 0);
        manager.swapCallback();
        assertEq(vault.balanceOf(feeCollector), 0);
        assertEq(vault.totalSupply(), supplyBefore);
    }

    function test_sweepCallback_smallBalance() public {
        deal(address(vault), address(manager), 1, true);
        uint256 supplyBefore = vault.totalSupply();
        vm.expectEmit(address(manager));
        emit SweepFinished(0, 1);
        manager.swapCallback();
        assertEq(vault.balanceOf(feeCollector), 1);
        assertEq(vault.totalSupply(), supplyBefore);

        deal(address(vault), address(manager), 2, true);
        supplyBefore = vault.totalSupply();
        vm.expectEmit(address(manager));
        emit SweepFinished(1, 1);
        manager.swapCallback();
        assertEq(vault.balanceOf(feeCollector), 1+1);
        assertEq(vault.totalSupply(), supplyBefore-1);
    }
}

contract OrigamiHOhmManagerMaxBorrow is OrigamiHOhmManagerTestBase {
    function test_maxBorrowFromCooler_noPosition() public {
        manager.maxBorrowFromCooler();
    }

    function test_maxBorrowFromCooler_borrowWithNoPriorSurplus_savings() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);
        assertEq(manager.coolerDebtInWad(), 29_616.4e18);
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e18);
        assertEq(sUSDS.balanceOf(address(manager)), 29_616.4e18);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        (uint96 oltv,) = cooler.loanToValues();
        assertEq(position.currentLtv, oltv);
    }

    function test_maxBorrowFromCooler_borrowWithNoPriorSurplus_notSavings() public {
        vm.startPrank(origamiMultisig);
        {
            manager.setPauser(address(origamiMultisig), true);
            manager.setPaused(IOrigamiManagerPausable.Paused(true, true));
            manager.setDebtTokenFromCooler(address(0));
        }

        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);
        assertEq(manager.coolerDebtInWad(), 29_616.4e18);
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e18);
        assertEq(USDS.balanceOf(address(manager)), 29_616.4e18);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        (uint96 oltv,) = cooler.loanToValues();
        assertEq(position.currentLtv, oltv);
    }

    function test_maxBorrowFromCooler_borrowWithSomePriorSurplus_savings() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        USDS.mint(address(manager), 3_300e18);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);
        assertEq(manager.coolerDebtInWad(), 29_616.4e18);
        assertEq(manager.surplusDebtTokenAmount(), 32_916.4e18);
        assertEq(sUSDS.balanceOf(address(manager)), 32_916.4e18);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        (uint96 oltv,) = cooler.loanToValues();
        assertEq(position.currentLtv, oltv);
    }

    function test_maxBorrowFromCooler_noChange() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);

        // Call again - no change
        assertEq(manager.maxBorrowFromCooler(), 0);
        assertEq(manager.coolerDebtInWad(), 29_616.4e18);
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e18);
        assertEq(sUSDS.balanceOf(address(manager)), 29_616.4e18);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        (uint96 oltv,) = cooler.loanToValues();
        assertEq(position.currentLtv, oltv);
    }

    function test_maxBorrowFromCooler_increasedOriginationLtv() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);

        skip(90 days);
        
        // Call again - since the LTV has increased (drip) we can borrow more
        assertEq(manager.maxBorrowFromCooler(), 627.434657077012722000e18);
        assertEq(manager.coolerDebtInWad(), 30_280.279452054734080000e18); // USDS
        // USDS - we've got some extra surplus from interest
        assertEq(manager.surplusDebtTokenAmount(), 30_974.102054337286694602e18);
        assertEq(sUSDS.balanceOf(address(manager)), 30_228.735962120614020133e18); // sUSDS
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        (uint96 oltv,) = cooler.loanToValues();
        assertEq(position.currentLtv, oltv);
    }

    function test_maxBorrowFromCooler_borrowDisabled() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);

        manager.setCoolerBorrowsDisabled(true);

        assertEq(manager.maxBorrowFromCooler(), 0);
        assertEq(manager.coolerDebtInWad(), 0);
        assertEq(manager.surplusDebtTokenAmount(), 0);
        assertEq(sUSDS.balanceOf(address(manager)), 0);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        assertEq(position.currentLtv, 0);
    }

    function test_maxBorrowFromCooler_repay() public {
        vm.startPrank(origamiMultisig);
        sUSDS.setInterestRate(0.01e18); // 1% yield
        cooler.setInterestRateWad(0.1e18); // 10% instead of only 0.5%
        
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.collateralTokenBalance(), 10e18);
        assertEq(manager.coolerDebtInWad(), 0);
        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);
        skip(90 days);

        {
            assertEq(manager.coolerDebtInWad(), 30_355.745152058925578989e18);
            assertEq(manager.surplusDebtTokenAmount(), 29_689.426739726027397260e18);

            assertEq(sUSDS.balanceOf(address(manager)), 29_616.4e18);
            assertEq(manager.debtTokenBalance(), 666.318412332898181729e18);
            assertEq(manager.debtTokenBalance(), manager.coolerDebtInWad()-manager.surplusDebtTokenAmount());

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertGt(position.currentLtv, oltv);
        }

        // This does a repay
        uint256 expectedRepayAmount = 75.465700004191498989e18;
        assertEq(manager.maxBorrowFromCooler(), -int256(expectedRepayAmount));

        {
            assertEq(manager.coolerDebtInWad(), 30_355.745152058925578989e18-expectedRepayAmount);
            assertEq(manager.surplusDebtTokenAmount(), 29_689.426739726027397260e18-expectedRepayAmount);

            assertEq(sUSDS.balanceOf(address(manager)), 29_541.119922105684894422e18);
            assertEq(manager.debtTokenBalance(), 666.318412332898181729e18);
            assertEq(manager.debtTokenBalance(), manager.coolerDebtInWad()-manager.surplusDebtTokenAmount());

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }
}

contract OrigamiHOhmManagerJoin is OrigamiHOhmManagerTestBase {
    event Join(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    function test_join_success_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, false));
        
        // Checking if paused is handled in the vault itself
        gOHM.mint(address(manager), 10e18);
        vm.startPrank(address(vault));
        manager.join(10e18, 3_300e18, alice, 1, 1);
    }

    function test_join_fail_notEnough() public {
        vm.startPrank(address(vault));
        
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e18;
        gOHM.mint(address(manager), collateralAmount-1);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.join(collateralAmount, debtAmount, alice, 1, 0);
    }

    function test_join_withBorrow_fresh() public {
        vm.startPrank(address(vault));
        
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e18;
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 1, 0);
        assertEq(USDS.balanceOf(alice), debtAmount);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedCoolerDebtDelta) - debtAmount);

            assertEq(sUSDS.balanceOf(address(manager)), uint256(expectedCoolerDebtDelta) - debtAmount);
            assertEq(manager.debtTokenBalance(), debtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_join_withBorrow_existing() public {
        vm.startPrank(address(vault));

        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e18;
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 1, 0);

        // And again        
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 1, 0);
        assertEq(USDS.balanceOf(alice), 2*debtAmount);

        {
            assertEq(manager.coolerDebtInWad(), 2*uint256(expectedCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), 2*(uint256(expectedCoolerDebtDelta) - debtAmount));

            assertEq(sUSDS.balanceOf(address(manager)), 2*(uint256(expectedCoolerDebtDelta) - debtAmount));
            assertEq(manager.debtTokenBalance(), 2*debtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_join_withRepay() public {
        vm.startPrank(origamiMultisig);
        sUSDS.setInterestRate(0.01e18); // 1% yield
        cooler.setInterestRateWad(0.1e18); // 10% instead of only 0.5%

        vm.startPrank(address(vault));
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e18;
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 1, 0);

        assertEq(manager.surplusDebtTokenAmount(), uint256(expectedCoolerDebtDelta) - debtAmount);

        skip(90 days);

        // Now accrued more debt than savings
        // and also more than the LTV oracle increase would allow.
        uint256 accruedDebtInterest = manager.coolerDebtInWad() - uint256(expectedCoolerDebtDelta);
        assertEq(accruedDebtInterest, 739.345152058925578989e18);
        uint256 surplusAfterSkip = manager.surplusDebtTokenAmount();
        uint256 accruedSavingsInterest = surplusAfterSkip - (uint256(expectedCoolerDebtDelta) - debtAmount);
        assertEq(accruedSavingsInterest, 64.889753424657534246e18);
      
        // Now add a little collateral and it should have to repay
        uint256 collateralAmount2 = 0.01e18;
        uint256 debtAmount2 = 300e18;

        int256 expectedCoolerDebtDelta2 = -45.185420552136764909e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount2, debtAmount2, alice, expectedCoolerDebtDelta2);
        manager.join(collateralAmount2, debtAmount2, alice, 1, 0);
        assertEq(USDS.balanceOf(alice), debtAmount+debtAmount2);

        {
            uint256 expectedDebt = uint256(expectedCoolerDebtDelta + expectedCoolerDebtDelta2) + accruedDebtInterest;
            assertEq(manager.coolerDebtInWad(), expectedDebt);
            uint256 newSurplus = manager.surplusDebtTokenAmount();
            assertEq(newSurplus, surplusAfterSkip - uint256(-expectedCoolerDebtDelta2) - debtAmount2);
            assertEq(manager.debtTokenBalance(), debtAmount + debtAmount2 + (accruedDebtInterest - accruedSavingsInterest));

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_join_withDelegate_overThreshold() public {
        vm.startPrank(address(vault));

        manager.updateDelegateAndAmount(alice, 0, 1, bob);
        check_accountDelegationBalances(alice, 0, 1, 0, bob, 0);
        check_dlgteSummary(0, 0, 0, 10);

        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e18;
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, bob, int256(collateralAmount/4));
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 25e18, 100e18);

        check_accountDelegationBalances(alice, 250, 1000, collateralAmount/4, bob, collateralAmount/4);
        check_dlgteSummary(collateralAmount, collateralAmount/4, 1, 10);
    }

    function test_join_withDelegate_underThreshold() public {
        vm.startPrank(address(vault));

        // Join on behalf of origamiMultisig first
        gOHM.mint(address(manager), 10e18);
        manager.join(10e18, 3_300e18, origamiMultisig, 100e18, 100e18);

        manager.updateDelegateAndAmount(alice, 0, 1, bob);
        check_accountDelegationBalances(alice, 0, 1, 0, bob, 0);
        check_dlgteSummary(10e18, 0, 0, 10);

        uint256 collateralAmount = 0.01e18;
        uint256 debtAmount = 30e18;
        int256 expectedCoolerDebtDelta = 29.6164e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 0.01e18, 10e18+0.01e18);

        check_accountDelegationBalances(alice, 0.01e18, 10e18+0.01e18, 0.01e18, bob, 0);
        check_dlgteSummary(10e18 + collateralAmount, 0, 0, 10);
    }
}

contract OrigamiHOhmManagerExit is OrigamiHOhmManagerTestBase {
    event Exit(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    function _join(uint256 collateralAmount, uint256 debtAmount) private {
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 1, 0);
    }

    function test_exit_success_paused() public {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, true));
        
        vm.startPrank(address(vault));
        _join(10e18, 3_300e18);

        // Checking if paused is handled in the vault itself
        manager.exit(1e18, 1_000e18, alice, alice, 1, 1);
    }

    function test_exit_withRepay_fresh() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        uint256 exitCollateralAmount = 2e18;
        uint256 exitDebtAmount = 1_000e18;
        int256 expectedExitCoolerDebtDelta = -5_923.28e18;
        USDS.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 1, 0);
        assertEq(gOHM.balanceOf(alice), exitCollateralAmount);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta) - (joinDebtAmount-exitDebtAmount));

            assertEq(sUSDS.balanceOf(address(manager)), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta) - (joinDebtAmount-exitDebtAmount));
            assertEq(manager.debtTokenBalance(), joinDebtAmount-exitDebtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_exit_withRepay_existing() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        uint256 exitCollateralAmount = 2e18;
        uint256 exitDebtAmount = 1_000e18;
        int256 expectedExitCoolerDebtDelta = -5_923.28e18;
        USDS.mint(address(manager), exitDebtAmount);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 1, 0);

        // And again
        USDS.mint(address(manager), exitDebtAmount);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 1, 0);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta) - (joinDebtAmount-2*exitDebtAmount));

            assertEq(sUSDS.balanceOf(address(manager)), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta) - (joinDebtAmount-2*exitDebtAmount));
            assertEq(manager.debtTokenBalance(), joinDebtAmount-2*exitDebtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_exit_withBorrow() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        skip(90 days);

        // Now accrued more debt than savings
        // and also more than the LTV oracle increase would allow.
        uint256 accruedDebtInterest = manager.coolerDebtInWad() - uint256(expectedJoinCoolerDebtDelta);
        assertEq(accruedDebtInterest, 36.444794977721358000e18);
        uint256 surplusAfterSkip = manager.surplusDebtTokenAmount();
        uint256 accruedSavingsInterest = surplusAfterSkip - (uint256(expectedJoinCoolerDebtDelta) - joinDebtAmount);
        assertEq(accruedSavingsInterest, 648.897534246575342465e18);
      
        uint256 exitCollateralAmount = 0.01e18;
        uint256 exitDebtAmount = 1_000e18;
        int256 expectedExitCoolerDebtDelta = 597.154377624957987920e18;
        USDS.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 1, 0);

        {
            uint256 expectedDebt = uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta) + accruedDebtInterest;
            assertEq(manager.coolerDebtInWad(), expectedDebt);
            uint256 newSurplus = manager.surplusDebtTokenAmount();
            assertEq(newSurplus, surplusAfterSkip + uint256(expectedExitCoolerDebtDelta) + exitDebtAmount);
            assertEq(manager.debtTokenBalance(), joinDebtAmount + accruedDebtInterest - accruedSavingsInterest - exitDebtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_exit_withDelegate_overThreshold() public {
        vm.startPrank(address(vault));

        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        _join(joinCollateralAmount, joinDebtAmount);
        assertEq(manager.collateralTokenBalance(), 10e18);
        
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, bob, int256(joinCollateralAmount*75/100)); // delegated 7.5e18
        manager.updateDelegateAndAmount(alice, 75, 100, bob);
        check_accountDelegationBalances(alice, 3, 4, joinCollateralAmount*3/4, bob, joinCollateralAmount*3/4);
        check_dlgteSummary(joinCollateralAmount, joinCollateralAmount*3/4, 1, 10);

        uint256 exitCollateralAmount = 2.5e18;
        uint256 exitDebtAmount = 1_000e18;
        int256 expectedExitCoolerDebtDelta = -7_404.1e18;
        USDS.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, bob, -int256(exitCollateralAmount));
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 5e18, 7.5e18);
        assertEq(manager.collateralTokenBalance(), 10e18-2.5e18);

        check_accountDelegationBalances(alice, 70, 100, 7.5e18*7/10, bob, 5e18);
        check_dlgteSummary(7.5e18, 7.5e18-2.5e18, 1, 10);
    }

    function test_exit_withDelegate_underThreshold() public {
        vm.startPrank(address(vault));

        // Join on behalf of origamiMultisig first
        gOHM.mint(address(manager), 10e18);
        manager.join(10e18, 3_300e18, origamiMultisig, 100e18, 100e18);

        uint256 joinCollateralAmount = 1e18;
        uint256 joinDebtAmount = 600e18;
        _join(joinCollateralAmount, joinDebtAmount);
        assertEq(manager.collateralTokenBalance(), 10e18 + 1e18);
        
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, bob, 1e18);
        manager.updateDelegateAndAmount(alice, 1e18, 11e18, bob);
        check_accountDelegationBalances(alice, 1e18, 11e18, 1e18, bob, 1e18);
        check_dlgteSummary(10e18 + joinCollateralAmount, 1e18, 1, 10);

        assertEq(manager.collateralTokenBalance(), 10e18+joinCollateralAmount);

        uint256 exitCollateralAmount = 0.95e18;
        uint256 exitDebtAmount = 500e18;
        int256 expectedExitCoolerDebtDelta = -2_813.558e18;
        USDS.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit DelegationApplied(alice, bob, -1e18); // The whole amount was undelegated
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(
            exitCollateralAmount, 
            exitDebtAmount, 
            alice, 
            alice, 
            joinCollateralAmount-exitCollateralAmount, 
            10e18+joinCollateralAmount-exitCollateralAmount
        );
        assertEq(manager.collateralTokenBalance(), 10e18+joinCollateralAmount-exitCollateralAmount);

        // Delegation was stripped
        check_accountDelegationBalances(
            alice, 
            joinCollateralAmount-exitCollateralAmount, 
            10e18+joinCollateralAmount-exitCollateralAmount, 
            0.05e18, 
            bob, // still remains
            0
        );
        check_dlgteSummary(10e18 + 0.05e18, 0, 0, 10);
    }

    function test_exit_fail_tooMuchUndelegationAmount() public {
        vm.startPrank(address(vault));

        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        _join(joinCollateralAmount, joinDebtAmount);
        assertEq(manager.collateralTokenBalance(), 10e18);
        
        manager.updateDelegateAndAmount(alice, 100, 100, bob);

        USDS.mint(address(manager), joinDebtAmount);
        manager.exit(10e18, joinDebtAmount, alice, alice, 100e18, 100e18);
    }
}

contract OrigamiHOhmManagerViews is OrigamiHOhmManagerTestBase {
    function test_supportsInterface() public view {
        assertEq(manager.supportsInterface(type(IOrigamiHOhmManager).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(manager.supportsInterface(type(IERC4626).interfaceId), false);
    }

    function test_convertSharesToCollateral_zeroSupply() public view {
        assertEq(manager.convertSharesToCollateral(123, 0), 0);
    }

    function test_convertSharesToCollateral_sharesTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidParam.selector));
        manager.convertSharesToCollateral(124, 123);
    }

    function test_convertSharesToCollateral_zeroCollateral() public view {
        assertEq(manager.convertSharesToCollateral(123, 123), 0);
    }

    function test_convertSharesToCollateral_someCollateralOverThreshold() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.convertSharesToCollateral(10e18, 100e18), 1e18);

        assertEq(manager.convertSharesToCollateral(100e18, 100e18), 10e18);
    }

    function test_convertSharesToCollateral_someCollateralUnderThreshold() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 1e18);
        gOHM.approve(address(cooler), 1e18);
        cooler.addCollateral(1e18, address(manager), new IDLGTEv1.DelegationRequest[](0));

        // Not affected by the cap
        assertEq(manager.convertSharesToCollateral(0.09e18, 1e18), 0.09e18);
    }
}

contract OrigamiHOhmManagerTestDelegations is OrigamiHOhmManagerTestBase {
    function _addCollateral(uint128 amount) private {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, amount);
        gOHM.approve(address(cooler), amount);
        cooler.addCollateral(amount, address(manager), new IDLGTEv1.DelegationRequest[](0));
    }

    function test_updateDelegateAndAmount_self() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, alice, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);
    }

    function test_updateDelegateAndAmount_other() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, bob);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, bob, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);

        manager.updateDelegateAndAmount(alice, 100e18, 100e18, origamiMultisig);
        check_accountDelegationBalances(alice, 100e18, 100e18, 10e18, origamiMultisig, 10e18);
        check_dlgteSummary(10e18, 10e18, 1, 10);
    }

    function test_updateDelegateAndAmount_remove() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, bob);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, bob, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);

        manager.updateDelegateAndAmount(alice, 10e18, 100e18, address(0));
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, address(0), 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_zeroSupply() public {
        _addCollateral(10e18);

        // no-op
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 0, alice);
        check_accountDelegationBalances(alice, 0, 100e18, 0, address(alice), 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_zeroShares() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 0, 100e18, alice);
        check_accountDelegationBalances(alice, 0, 100e18, 0, address(alice), 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_noCollateral() public {
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, bob);
        check_dlgteSummary(0, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_manyUsers() public {
        vm.startPrank(origamiMultisig);
        cooler.setMaxDelegateAddresses(address(manager), 100_000);

        uint128 totalCollateral = 100_000e18;
        _addCollateral(totalCollateral);
        vm.startPrank(address(vault));

        address user;
        uint256 numAddresses = 1_000;
        for (uint256 i; i < numAddresses; ++i) {
            user = makeAddr(vm.toString(i));
            manager.updateDelegateAndAmount(user, 1e18, 1e18 * numAddresses, user);
        }
        check_dlgteSummary(totalCollateral, totalCollateral, numAddresses, 100_000);
    }

    function test_updateDelegateAndAmount_ohmBackingIncrease() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, alice, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);

        _addCollateral(10e18);
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        check_accountDelegationBalances(alice, 10e18, 100e18, 2e18, alice, 2e18);
        check_dlgteSummary(20e18, 2e18, 1, 10);
    }

    function test_setDelegationAmount1_noCollateral() public {
        vm.startPrank(address(vault));
        manager.setDelegationAmount1(alice, 10e18, 100e18);
        check_dlgteSummary(0, 0, 0, 10);
    }

    function test_setDelegationAmount1_noPrior() public {
        _addCollateral(10e18);

        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, address(0), 0);

        // noop if the delegate isn't set first
        vm.startPrank(address(vault));
        manager.setDelegationAmount1(alice, 10e18, 100e18);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, address(0), 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_setDelegationAmount1_noChange() public {
        _addCollateral(10e18);
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        manager.setDelegationAmount1(alice, 10e18, 100e18);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, alice, 1e18);
    }

    function test_setDelegationAmount1_increase_decrease() public {
        _addCollateral(10e18);
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        manager.setDelegationAmount1(alice, 20e18, 100e18);
        check_accountDelegationBalances(alice, 20e18, 100e18, 2e18, alice, 2e18);
        manager.setDelegationAmount1(alice, 0, 100e18);
        check_accountDelegationBalances(alice, 0, 100e18, 0, alice, 0);
    }

    function test_setDelegationAmount2_noPrior() public {
        _addCollateral(10e18);

        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, address(0), 0);
        check_accountDelegationBalances(bob, 20e18, 100e18, 2e18, address(0), 0);

        // noop if the delegate isn't set first
        vm.startPrank(address(vault));
        manager.setDelegationAmount2(alice, 10e18, bob, 20e18, 100e18);
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, address(0), 0);
        check_accountDelegationBalances(bob, 20e18, 100e18, 2e18, address(0), 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_setDelegationAmount2_noChange() public {
        _addCollateral(10e18);
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 10e18, 100e18, alice);
        manager.updateDelegateAndAmount(bob, 20e18, 100e18, bob);
        manager.setDelegationAmount2(alice, 10e18, bob, 25e18, 100e18); // bob increased
        check_accountDelegationBalances(alice, 10e18, 100e18, 1e18, alice, 1e18);
        check_accountDelegationBalances(bob, 25e18, 100e18, 2.5e18, bob, 2.5e18);
    }

    function test_setDelegationAmount2_increase_decrease() public {
        _addCollateral(10e18);
        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 20e18, 100e18, alice);
        check_accountDelegationBalances(alice, 20e18, 100e18, 2e18, alice, 2e18);
        check_accountDelegationBalances(bob, 0, 100e18, 0, address(0), 0); // bob didn't set his up

        manager.setDelegationAmount2(alice, 15e18, bob, 5e18, 100e18);
        check_accountDelegationBalances(alice, 15e18, 100e18, 1.5e18, alice, 1.5e18);
        check_accountDelegationBalances(bob, 5e18, 100e18, 0.5e18, address(0), 0); // bob didn't set his up

        manager.setDelegationAmount2(alice, 0, bob, 20e18, 100e18);
        check_accountDelegationBalances(alice, 0, 100e18, 0, alice, 0);
    }
}

contract OrigamiHOhmManagerTestDelegationThreshold is OrigamiHOhmManagerTestBase {
    function _addCollateral(uint128 amount) private {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, amount);
        gOHM.approve(address(cooler), amount);
        cooler.addCollateral(amount, address(manager), new IDLGTEv1.DelegationRequest[](0));
    }

    function test_updateDelegateAndAmount_underThreshold_fromNoDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 0.09e18, 10e18, alice);
        check_accountDelegationBalances(alice, 0.09e18, 10e18, 0.09e18, alice, 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_underThreshold_fromSomeDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 1e18, 10e18, alice);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);

        manager.updateDelegateAndAmount(alice, 0.09e18, 10e18, alice);
        check_accountDelegationBalances(alice, 0.09e18, 10e18, 0.09e18, alice, 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_updateDelegateAndAmount_atThreshold() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 0.1e18, 10e18, alice);
        check_accountDelegationBalances(alice, 0.1e18, 10e18, 0.1e18, alice, 0.1e18);
        check_dlgteSummary(10e18, 0.1e18, 1, 10);
    }

    function test_setDelegationAmount1_underThreshold_fromNoDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 0, 10e18, alice);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 0);
        check_dlgteSummary(10e18, 0, 0, 10);

        manager.setDelegationAmount1(alice, 0.09e18, 10e18);
        check_accountDelegationBalances(alice, 0.09e18, 10e18, 0.09e18, alice, 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_setDelegationAmount1_underThreshold_fromSomeDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 1e18, 10e18, alice);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 1e18);
        check_dlgteSummary(10e18, 1e18, 1, 10);

        manager.setDelegationAmount1(alice, 0.09e18, 10e18);
        check_accountDelegationBalances(alice, 0.09e18, 10e18, 0.09e18, alice, 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }

    function test_setDelegationAmount2_underThreshold_fromNoDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 0, 10e18, alice);
        manager.updateDelegateAndAmount(bob, 0, 10e18, bob);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 0);
        check_accountDelegationBalances(bob, 1e18, 10e18, 1e18, bob, 0);
        check_dlgteSummary(10e18, 0, 0, 10);

        manager.setDelegationAmount2(alice, 0.09e18, bob, 0.09e18, 10e18);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 0);
        check_accountDelegationBalances(bob, 1e18, 10e18, 1e18, bob, 0);
        check_dlgteSummary(10e18, 0, 0, 10);

        manager.setDelegationAmount2(alice, 0.1e18, bob, 0.1e18, 10e18);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 0.1e18);
        check_accountDelegationBalances(bob, 1e18, 10e18, 1e18, bob, 0.1e18);
        check_dlgteSummary(10e18, 0.2e18, 2, 10);
    }

    function test_setDelegationAmount2_underThreshold_fromSomeDelegation() public {
        _addCollateral(10e18);

        vm.startPrank(address(vault));
        manager.updateDelegateAndAmount(alice, 1e18, 10e18, alice);
        manager.updateDelegateAndAmount(bob, 1e18, 10e18, bob);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 1e18);
        check_accountDelegationBalances(bob, 1e18, 10e18, 1e18, bob, 1e18);
        check_dlgteSummary(10e18, 2e18, 2, 10);

        manager.setDelegationAmount2(alice, 0.09e18, bob, 0.09e18, 10e18);
        check_accountDelegationBalances(alice, 1e18, 10e18, 1e18, alice, 0);
        check_accountDelegationBalances(bob, 1e18, 10e18, 1e18, bob, 0);
        check_dlgteSummary(10e18, 0, 0, 10);
    }
}