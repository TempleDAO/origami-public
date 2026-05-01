pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiHOhmManager } from "contracts/investments/olympus/OrigamiHOhmManager.sol";
import { IOrigamiHOhmManager } from "contracts/interfaces/investments/olympus/IOrigamiHOhmManager.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { DLGTEv1 as IDLGTEv1 } from "contracts/test/external/olympus/src/modules/DLGTE/DLGTE.v1.sol";
import { Kernel, Actions } from "contracts/test/external/olympus/src/policies/RolesAdmin.sol";
import { IMonoCooler } from "contracts/test/external/olympus/src/policies/interfaces/cooler/IMonoCooler.sol";

import { MockCoolerTreasuryBorrower } from "test/foundry/mocks/external/olympus/MockCoolerTreasuryBorrower.m.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { DummyDexRouter } from "contracts/test/common/swappers/DummyDexRouter.sol";
import { MockSUsdsToken } from "contracts/test/external/maker/MockSUsdsToken.m.sol";
import { IOrigamiSwapper } from "contracts/interfaces/common/swappers/IOrigamiSwapper.sol";

import { OrigamiHOhmManagerTestBase } from "./OrigamiHOhmManager.t.sol";

contract OrigamiHOhmManagerDebtTokenChangeTestBase is OrigamiHOhmManagerTestBase {
    uint96 internal constant DEFAULT_SWEEP_MAX_SELL_USDC = 1_000e6;
    uint256 internal constant INITIAL_TRSRY_MINT = 33_000_000e18;

    MockSUsdsToken internal sUSDC;

    function setUp() public virtual override {
        OrigamiHOhmManagerTestBase.setUp();

        sUSDC = new MockSUsdsToken(USDC);
        sUSDC.setInterestRate(0.10e18);

        // Mint some USDC to Ohm treasury
        USDC.mint(address(treasuryBorrower.TRSRY()), INITIAL_TRSRY_MINT);

        // Fund others with sUSDC to start the interest ticking
        USDC.mint(address(this), INITIAL_TRSRY_MINT * 3);
        USDC.approve(address(sUSDC), INITIAL_TRSRY_MINT * 3);
        sUSDC.deposit(INITIAL_TRSRY_MINT * 3, OTHERS);

        changeDebtToken();
    }

    function changeDebtToken() internal {
        vm.startPrank(origamiMultisig);
        manager.setPauser(origamiMultisig, true);
        manager.setPaused(IOrigamiManagerPausable.Paused(true, true));

        MockCoolerTreasuryBorrower newTreasuryBorrower = new MockCoolerTreasuryBorrower(address(kernel), address(USDC));
        kernel.executeAction(Actions.ActivatePolicy, address(newTreasuryBorrower));
        cooler.setTreasuryBorrower(address(newTreasuryBorrower));
        kernel.executeAction(Actions.DeactivatePolicy, address(treasuryBorrower));

        manager.setDebtTokenFromCooler(address(sUSDC));
        manager.setSweepParams(DEFAULT_SWEEP_COOLDOWN, DEFAULT_SWEEP_MAX_SELL_USDC);
        manager.setPaused(IOrigamiManagerPausable.Paused(false, false));
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestAdmin is OrigamiHOhmManagerDebtTokenChangeTestBase {
    function test_initialization() public view {
        assertEq(manager.owner(), origamiMultisig);
        assertEq(address(manager.vault()), address(vault));
        assertEq(address(manager.cooler()), address(cooler));
        assertEq(address(manager.collateralToken()), address(gOHM));
        assertEq(address(manager.debtToken()), address(USDC));
        assertEq(address(manager.debtTokenSavingsVault()), address(sUSDC));
        assertEq(manager.debtTokenDecimalsToWadScalar(), 1e12);
        assertEq(manager.exitFeeBps(), 0);
        assertEq(manager.coolerBorrowsDisabled(), false);
        assertEq(address(manager.sweepSwapper()), address(sweepSwapper));
        assertEq(manager.sweepCooldownSecs(), 1 days);
        assertEq(manager.lastSweepTime(), 0);
        assertEq(manager.maxSweepSellAmount(), 1_000e6);
        assertEq(manager.MAX_EXIT_FEE_BPS(), 330);

        assertEq(gOHM.allowance(address(manager), address(cooler)), type(uint256).max);
        assertEq(USDS.allowance(address(manager), address(cooler)), 0);
        assertEq(USDS.allowance(address(manager), address(sUSDS)), 0);
        assertEq(USDC.allowance(address(manager), address(cooler)), type(uint256).max);
        
        assertEq(manager.areJoinsPaused(), false);
        assertEq(manager.areExitsPaused(), false);
        assertEq(manager.debtTokenBalance(), 0);
        assertEq(manager.coolerDebtInWad(), 0);
        assertEq(manager.surplusDebtTokenAmount(), 0);
        assertEq(manager.collateralTokenBalance(), 0);
    }

    function test_recoverToken_success() public {
        // Can now recover USDS or sUSDS
        USDS.mint(address(manager), 100e18);
        manager.recoverToken(address(USDS), alice, 100e18);
        assertEq(USDS.balanceOf(alice), 100e18);

        deal(address(sUSDS), address(manager), 100e18);
        manager.recoverToken(address(sUSDS), alice, 100e18);
        assertEq(sUSDS.balanceOf(alice), 100e18);
    }

    function test_recoverToken_fail() public {
        // Can't recover USDC now
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(USDC)));
        manager.recoverToken(address(USDC), alice, 123);
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestSavings is OrigamiHOhmManagerDebtTokenChangeTestBase {
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
        deal(address(USDC), address(manager), 100e6);
        manager.syncDebtTokenSavings(1e6);
        assertEq(USDC.balanceOf(address(manager)), 100e6);
    }

    function test_syncDebtTokenSavings_deposit() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 100e6);

        skip(365 days);

        manager.syncDebtTokenSavings(33e6);
        assertEq(USDC.balanceOf(address(manager)), 33e6);
        assertEq(sUSDC.balanceOf(address(manager)), 60.909090e6);

        assertEq(manager.surplusDebtTokenAmount(), 100e6 - 1);
    }

    function test_syncDebtTokenSavings_withdraw_noCap() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDC), address(manager), 33e6);
        deal(address(sUSDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 133e6);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e6);
        manager.syncDebtTokenSavings(133e6);
        assertEq(USDC.balanceOf(address(manager)), 133e6);
        assertEq(sUSDC.balanceOf(address(manager)), 9.090909e6);

        assertEq(manager.surplusDebtTokenAmount(), 143e6 - 1);
    }

    function test_syncDebtTokenSavings_withdraw_zeroMaxWithdraw() public {
        vm.mockCall(
            address(sUSDC),
            abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(manager)),
            abi.encode(0)
        );

        vm.startPrank(origamiMultisig);
        deal(address(USDC), address(manager), 33e6);
        deal(address(sUSDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 133e6);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e6);
        manager.syncDebtTokenSavings(133e6);

        assertEq(USDC.balanceOf(address(manager)), 33e6);
        assertEq(sUSDC.balanceOf(address(manager)), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 143e6);
    }

    function test_syncDebtTokenSavings_noDifference() public {
        vm.startPrank(origamiMultisig);
        deal(address(USDC), address(manager), 33e6);
        deal(address(sUSDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 133e6);

        skip(365 days);
        assertEq(manager.surplusDebtTokenAmount(), 143e6);
        manager.syncDebtTokenSavings(33e6);
        
        assertEq(USDC.balanceOf(address(manager)), 33e6);
        assertEq(sUSDC.balanceOf(address(manager)), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 143e6);
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestSweep is OrigamiHOhmManagerDebtTokenChangeTestBase {
    event SweepStarted(address indexed debtToken, uint256 debtTokenAmount);
    event SweepFinished(uint256 hohmBurned, uint256 feeAmount);

    function test_sweep_fail_tooMuch() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiHOhmManager.SweepTooLarge.selector));
        manager.sweep(DEFAULT_SWEEP_MAX_SELL_USDC + 1, bytes(""));

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.sweep(DEFAULT_SWEEP_MAX_SELL_USDC, bytes(""));
    }

    function test_sweep_withSavingsVault() public {
        vm.startPrank(origamiMultisig);

        uint128 currentTimestamp = uint128(vm.getBlockTimestamp());
        skip(30 days);

        deal(address(sUSDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 100.821917e6);

        bytes memory encodedRouteData = abi.encode(
            IOrigamiSwapper.RouteDataWithCallback({
                router: address(dexRouter),
                minBuyAmount: 0,
                receiver: address(manager),
                data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(sUSDC), 33e6, address(vault), 10e18))
            })
        );

        assertEq(vault.totalSupply(), 1_000_000e18);
        vm.expectEmit(address(manager));
        emit SweepStarted(address(sUSDC), 33e6);
        vm.expectEmit(address(manager));
        emit SweepFinished(9.67e18, 0.33e18);
        manager.sweep(33e6, encodedRouteData);
        assertEq(vault.totalSupply(), 1_000_000e18 - 9.67e18);
        assertEq(vault.balanceOf(feeCollector), 0.33e18);
        assertEq(sUSDC.balanceOf(address(manager)), 67e6);
        assertEq(manager.surplusDebtTokenAmount(), 67.550684e6);
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

        deal(address(USDC), address(manager), 100e6);
        assertEq(manager.surplusDebtTokenAmount(), 100e6);

        bytes memory encodedRouteData = abi.encode(
            IOrigamiSwapper.RouteDataWithCallback({
                router: address(dexRouter),
                minBuyAmount: 0,
                receiver: address(manager),
                data: abi.encodeCall(DummyDexRouter.doExactSwap, (address(USDC), 33e6, address(vault), 10e18))
            })
        );

        assertEq(vault.totalSupply(), 1_000_000e18);
        vm.expectEmit(address(manager));
        emit SweepStarted(address(USDC), 33e6);
        vm.expectEmit(address(manager));
        emit SweepFinished(9.67e18, 0.33e18);
        manager.sweep(33e6, encodedRouteData);
        assertEq(vault.totalSupply(), 1_000_000e18 - 9.67e18);
        assertEq(vault.balanceOf(feeCollector), 0.33e18);
        assertEq(USDC.balanceOf(address(manager)), 67e6);
        assertEq(manager.surplusDebtTokenAmount(), 67e6);
        assertEq(manager.lastSweepTime(), currentTimestamp + uint128(30 days));
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestMaxBorrow is OrigamiHOhmManagerDebtTokenChangeTestBase {
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
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e6);
        assertEq(sUSDC.balanceOf(address(manager)), 29_616.4e6);
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
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e6);
        assertEq(USDC.balanceOf(address(manager)), 29_616.4e6);
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

        USDC.mint(address(manager), 3_300e6);

        assertEq(manager.maxBorrowFromCooler(), 29_616.4e18);
        assertEq(manager.coolerDebtInWad(), 29_616.4e18);
        assertEq(manager.surplusDebtTokenAmount(), 32_916.4e6);
        assertEq(sUSDC.balanceOf(address(manager)), 32_916.4e6);
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
        assertEq(manager.surplusDebtTokenAmount(), 29_616.4e6);
        assertEq(sUSDC.balanceOf(address(manager)), 29_616.4e6);
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
        assertEq(manager.coolerDebtInWad(), 30_280.279452054734080000e18); // USDC
        // USDC - we've got some extra surplus from interest
        assertEq(manager.surplusDebtTokenAmount(), 30_974.102055e6);
        assertEq(sUSDC.balanceOf(address(manager)), 30_228.735963e6); // sUSDC
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
        assertEq(sUSDC.balanceOf(address(manager)), 0);
        assertEq(manager.debtTokenBalance(), 0);

        IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
        assertEq(position.currentLtv, 0);
    }

    function test_maxBorrowFromCooler_repay() public {
        vm.startPrank(origamiMultisig);
        sUSDC.setInterestRate(0.01e18); // 1% yield
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
            assertEq(manager.surplusDebtTokenAmount(), 29_689.426739e6);

            assertEq(sUSDC.balanceOf(address(manager)), 29_616.4e6);
            assertEq(manager.debtTokenBalance(), 666.318414e6);
            assertEq(manager.debtTokenBalance(), manager.coolerDebtInWad() / 1e12 - manager.surplusDebtTokenAmount() + 1);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertGt(position.currentLtv, oltv);
        }

        // This does a repay
        uint256 expectedRepayAmount = 75.465700004191498989e18;
        assertEq(manager.maxBorrowFromCooler(), -int256(expectedRepayAmount));

        {
            assertEq(manager.coolerDebtInWad(), 30_355.745152058925578989e18-expectedRepayAmount);
            assertEq(manager.surplusDebtTokenAmount(), (29_689.426739726027397260e18-expectedRepayAmount)/1e12 - 1);

            assertEq(sUSDC.balanceOf(address(manager)), 29_541.119921e6);
            assertEq(manager.debtTokenBalance(), 666.318415e6);
            assertEq(manager.debtTokenBalance(), manager.coolerDebtInWad() / 1e12 - manager.surplusDebtTokenAmount() + 1);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestJoin is OrigamiHOhmManagerDebtTokenChangeTestBase {
    event Join(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    function test_join_fail_notEnough() public {
        vm.startPrank(address(vault));
        
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e6;
        gOHM.mint(address(manager), collateralAmount-1);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        manager.join(collateralAmount, debtAmount, alice, 123, 123);
    }

    function test_join_withBorrow_fresh() public {
        vm.startPrank(address(vault));
        
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e6;
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 123, 123);
        assertEq(USDC.balanceOf(alice), debtAmount);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedCoolerDebtDelta)/1e12 - debtAmount);

            assertEq(sUSDC.balanceOf(address(manager)), uint256(expectedCoolerDebtDelta)/1e12 - debtAmount);
            assertEq(manager.debtTokenBalance(), debtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_join_withBorrow_existing() public {
        vm.startPrank(address(vault));

        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e6;
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 123, 123);

        // And again        
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount, debtAmount, alice, expectedCoolerDebtDelta);
        manager.join(collateralAmount, debtAmount, alice, 123, 123);
        assertEq(USDC.balanceOf(alice), 2*debtAmount);

        {
            assertEq(manager.coolerDebtInWad(), 2*uint256(expectedCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), 2*(uint256(expectedCoolerDebtDelta)/1e12 - debtAmount));

            assertEq(sUSDC.balanceOf(address(manager)), 2*(uint256(expectedCoolerDebtDelta)/1e12 - debtAmount));
            assertEq(manager.debtTokenBalance(), 2*debtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_join_withRepay() public {
        vm.startPrank(origamiMultisig);
        sUSDC.setInterestRate(0.01e18); // 1% yield
        cooler.setInterestRateWad(0.1e18); // 10% instead of only 0.5%

        vm.startPrank(address(vault));
        uint256 collateralAmount = 10e18;
        uint256 debtAmount = 3_300e6;
        int256 expectedCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 123, 123);

        assertEq(manager.surplusDebtTokenAmount(), uint256(expectedCoolerDebtDelta)/1e12 - debtAmount);

        skip(90 days);

        // Now accrued more debt than savings
        // and also more than the LTV oracle increase would allow.
        uint256 accruedDebtInterest = manager.coolerDebtInWad() - uint256(expectedCoolerDebtDelta);
        assertEq(accruedDebtInterest, 739.345152058925578989e18);
        uint256 surplusAfterSkip = manager.surplusDebtTokenAmount();
        uint256 accruedSavingsInterest = surplusAfterSkip*1e12 - (uint256(expectedCoolerDebtDelta) - debtAmount*1e12);
        assertEq(accruedSavingsInterest, 64.889753e18);
      
        // Now add a little collateral and it should have to repay
        uint256 collateralAmount2 = 0.01e18;
        uint256 debtAmount2 = 300e6;

        int256 expectedCoolerDebtDelta2 = -45.185420552136764909e18;
        gOHM.mint(address(manager), collateralAmount);
        vm.expectEmit(address(manager));
        emit Join(collateralAmount2, debtAmount2, alice, expectedCoolerDebtDelta2);
        manager.join(collateralAmount2, debtAmount2, alice, 123, 123);
        assertEq(USDC.balanceOf(alice), debtAmount+debtAmount2);

        {
            uint256 expectedDebt = uint256(expectedCoolerDebtDelta + expectedCoolerDebtDelta2) + accruedDebtInterest;
            assertEq(manager.coolerDebtInWad(), expectedDebt);
            uint256 newSurplus = manager.surplusDebtTokenAmount();
            assertEq(newSurplus, surplusAfterSkip - uint256(-expectedCoolerDebtDelta2)/1e12 - debtAmount2 - 2);
            assertEq(manager.debtTokenBalance(), (debtAmount + debtAmount2) + (accruedDebtInterest - accruedSavingsInterest)/1e12 + 2);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestExit is OrigamiHOhmManagerDebtTokenChangeTestBase {
    event Exit(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    function _join(uint256 collateralAmount, uint256 debtAmount) private {
        gOHM.mint(address(manager), collateralAmount);
        manager.join(collateralAmount, debtAmount, alice, 123, 123);
    }

    function test_exit_withRepay_fresh() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e6;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        uint256 exitCollateralAmount = 2e18;
        uint256 exitDebtAmount = 1_000e6;
        int256 expectedExitCoolerDebtDelta = -5_923.28e18;
        USDC.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 123, 123);
        assertEq(gOHM.balanceOf(alice), exitCollateralAmount);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta)/1e12 - (joinDebtAmount-exitDebtAmount));

            assertEq(sUSDC.balanceOf(address(manager)), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta)/1e12 - (joinDebtAmount-exitDebtAmount));
            assertEq(manager.debtTokenBalance(), joinDebtAmount-exitDebtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_exit_withRepay_existing() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e6;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        uint256 exitCollateralAmount = 2e18;
        uint256 exitDebtAmount = 1_000e6;
        int256 expectedExitCoolerDebtDelta = -5_923.28e18;
        USDC.mint(address(manager), exitDebtAmount);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 123, 123);

        // And again
        USDC.mint(address(manager), exitDebtAmount);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 123, 123);

        {
            assertEq(manager.coolerDebtInWad(), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta));
            assertEq(manager.surplusDebtTokenAmount(), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta)/1e12 - (joinDebtAmount-2*exitDebtAmount));

            assertEq(sUSDC.balanceOf(address(manager)), uint256(expectedJoinCoolerDebtDelta + 2*expectedExitCoolerDebtDelta)/1e12 - (joinDebtAmount-2*exitDebtAmount));
            assertEq(manager.debtTokenBalance(), joinDebtAmount-2*exitDebtAmount);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }

    function test_exit_withBorrow() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e6;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        _join(joinCollateralAmount, joinDebtAmount);

        skip(90 days);

        // Now accrued more debt than savings
        // and also more than the LTV oracle increase would allow.
        uint256 accruedDebtInterest = manager.coolerDebtInWad() - uint256(expectedJoinCoolerDebtDelta);
        assertEq(accruedDebtInterest, 36.444794977721358000e18);
        uint256 surplusAfterSkip = manager.surplusDebtTokenAmount();
        uint256 accruedSavingsInterest = surplusAfterSkip*1e12 - (uint256(expectedJoinCoolerDebtDelta) - joinDebtAmount*1e12);
        assertEq(accruedSavingsInterest, 648.897534e18);
      
        uint256 exitCollateralAmount = 0.01e18;
        uint256 exitDebtAmount = 1_000e6;
        int256 expectedExitCoolerDebtDelta = 597.154377624957987920e18;
        USDC.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 123, 123);

        {
            uint256 expectedDebt = uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta) + accruedDebtInterest;
            assertEq(manager.coolerDebtInWad(), expectedDebt);
            uint256 newSurplus = manager.surplusDebtTokenAmount();
            assertEq(newSurplus, surplusAfterSkip + uint256(expectedExitCoolerDebtDelta)/1e12 + exitDebtAmount);
            assertEq(manager.debtTokenBalance(), joinDebtAmount + accruedDebtInterest/1e12 - accruedSavingsInterest/1e12 - exitDebtAmount + 2);

            IMonoCooler.AccountPosition memory position = cooler.accountPosition(address(manager));
            (uint96 oltv,) = cooler.loanToValues();
            assertEq(position.currentLtv, oltv);
        }
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestExitAfterChange is OrigamiHOhmManagerDebtTokenChangeTestBase {
    event Exit(uint256 collateralAmount, uint256 debtAmount, address receiver, int256 coolerDebtDeltaInWad);

    // Don't change yet
    function setUp() public virtual override {
        OrigamiHOhmManagerTestBase.setUp();

        sUSDC = new MockSUsdsToken(USDC);
        sUSDC.setInterestRate(0.10e18);

        // Mint some USDC to Ohm treasury
        USDC.mint(address(treasuryBorrower.TRSRY()), INITIAL_TRSRY_MINT);

        // Fund others with sUSDC to start the interest ticking
        USDC.mint(address(this), INITIAL_TRSRY_MINT * 3);
        USDC.approve(address(sUSDC), INITIAL_TRSRY_MINT * 3);
        sUSDC.deposit(INITIAL_TRSRY_MINT * 3, OTHERS);
    }

    function test_exit_afterChange() public {
        vm.startPrank(address(vault));
        
        uint256 joinCollateralAmount = 10e18;
        uint256 joinDebtAmount = 3_300e18;
        int256 expectedJoinCoolerDebtDelta = 29_616.4e18;
        gOHM.mint(address(manager), joinCollateralAmount);
        manager.join(joinCollateralAmount, joinDebtAmount, alice, 123, 123);
        assertEq(USDS.balanceOf(alice), joinDebtAmount);

        skip(90 days);
        uint256 expectedDebtInterest = 36.444794977721358000e18;

        // Pull all back to USDS first
        uint256 surplusBefore = manager.surplusDebtTokenAmount();
        vm.startPrank(origamiMultisig);
        manager.syncDebtTokenSavings(type(uint256).max);
        changeDebtToken();

        uint256 balance = USDS.balanceOf(address(manager));
        manager.recoverToken(address(USDS), address(origamiMultisig), balance);
        USDC.mint(address(manager), balance/1e12);
        assertEq(manager.surplusDebtTokenAmount(), surplusBefore/1e12);

        vm.startPrank(address(vault));

        uint256 exitCollateralAmount = 2e18;
        uint256 exitDebtAmount = 1_000e6;
        int256 expectedExitCoolerDebtDelta = -5_428.621233333934094000e18;
        USDC.mint(address(manager), exitDebtAmount);
        vm.expectEmit(address(manager));
        emit Exit(exitCollateralAmount, exitDebtAmount, alice, expectedExitCoolerDebtDelta);
        manager.exit(exitCollateralAmount, exitDebtAmount, alice, alice, 123, 123);

        assertEq(manager.coolerDebtInWad(), uint256(expectedJoinCoolerDebtDelta + expectedExitCoolerDebtDelta) + expectedDebtInterest);
        assertEq(manager.surplusDebtTokenAmount(), 22_536.676299e6);
    }
}

contract OrigamiHOhmManagerDebtTokenChangeTestViews is OrigamiHOhmManagerDebtTokenChangeTestBase {
    function test_convertSharesToCollateral_someCollateral() public {
        vm.startPrank(origamiMultisig);
        gOHM.mint(origamiMultisig, 10e18);
        gOHM.approve(address(cooler), 10e18);
        cooler.addCollateral(10e18, address(manager), new IDLGTEv1.DelegationRequest[](0));
        assertEq(manager.convertSharesToCollateral(10e18, 100e18), 1e18);

        assertEq(manager.convertSharesToCollateral(100e18, 100e18), 10e18);
    }
}
