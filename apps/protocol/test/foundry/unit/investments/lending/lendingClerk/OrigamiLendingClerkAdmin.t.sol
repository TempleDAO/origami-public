pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiLendingClerkTestBase, MockBorrower } from "./OrigamiLendingClerkBase.t.sol";
import { OrigamiLendingClerk } from "contracts/investments/lending/OrigamiLendingClerk.sol";

import { DummyMintableToken } from "contracts/test/common/DummyMintableToken.sol";
import { IOrigamiDebtToken } from "contracts/interfaces/investments/lending/IOrigamiDebtToken.sol";
import { LinearWithKinkInterestRateModel } from "contracts/common/interestRate/LinearWithKinkInterestRateModel.sol";

import { OrigamiLendingClerk } from "contracts/investments/lending/OrigamiLendingClerk.sol";
import { IOrigamiLendingClerk } from "contracts/interfaces/investments/lending/IOrigamiLendingClerk.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiLendingClerkTestAdmin is OrigamiLendingClerkTestBase {
    event SupplyManagerSet(address indexed supplyManager);
    event GlobalPausedSet(bool pauseBorrow, bool pauseRepays);
    event BorrowerPausedSet(address indexed borrower, bool pauseBorrow, bool pauseRepays);
    event InterestRateModelUpdated(address indexed borrower, address indexed interestRateModel);
    event BorrowerAdded(address indexed borrower, address indexed interestRateModel, string name, string version);
    event DebtCeilingUpdated(address indexed borrower, uint256 oldDebtCeiling, uint256 newDebtCeiling);
    event BorrowerShutdown(address indexed borrower, uint256 outstandingDebt);

    event InterestRateSet(address indexed debtor, uint96 rate);
    event Checkpoint(address indexed debtor, uint128 principal, uint128 interest);

    function test_initialization() public {
        assertEq(lendingClerk.owner(), origamiMultisig);
        assertEq(address(lendingClerk.asset()), address(usdcToken));
        assertEq(address(lendingClerk.oToken()), address(oUsdc));
        assertEq(address(lendingClerk.idleStrategyManager()), address(idleStrategyManager));
        assertEq(address(lendingClerk.debtToken()), address(iUsdc));
        assertEq(address(lendingClerk.circuitBreakerProxy()), address(cbProxy));
        assertEq(lendingClerk.supplyManager(), supplyManager);
        assertEq(lendingClerk.globalBorrowPaused(), false);
        assertEq(lendingClerk.globalRepayPaused(), false);
        assertEq(address(lendingClerk.globalInterestRateModel()), address(globalInterestRateModel));

        address[] memory borrowers = lendingClerk.borrowersList();
        assertEq(borrowers.length, 0);
        assertEq(lendingClerk.totalAvailableToWithdraw(), 0);
        assertEq(lendingClerk.calculateGlobalInterestRate(), GLOBAL_IR_AT_0_UR);
        assertEq(lendingClerk.globalUtilisationRatio(), 0);
        assertEq(lendingClerk.totalBorrowerDebt(), 0);
    }

    function test_construction_fail() public {
        DummyMintableToken token24 = new DummyMintableToken(origamiMultisig, "Deposit Token", "token", 24);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(token24)));
        new OrigamiLendingClerk(
            origamiMultisig, 
            address(token24), 
            address(oUsdc), 
            address(idleStrategyManager),
            address(iUsdc),
            address(cbProxy),
            supplyManager,
            address(globalInterestRateModel)
        );

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidToken.selector, address(iUsdc)));
        new OrigamiLendingClerk(
            origamiMultisig, 
            address(usdcToken), 
            address(token24), 
            address(idleStrategyManager),
            address(iUsdc),
            address(cbProxy),
            supplyManager,
            address(globalInterestRateModel)
        );
    }

    function test_setSupplyManager_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lendingClerk.setSupplyManager(address(0));
    }

    function test_setSupplyManager_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lendingClerk));
        emit SupplyManagerSet(alice);
        lendingClerk.setSupplyManager(alice);
        assertEq(lendingClerk.supplyManager(), alice);
    }

    function test_setGlobalPaused_success() public {
        vm.startPrank(origamiMultisig);

        vm.expectEmit(address(lendingClerk));
        emit GlobalPausedSet(true, false);
        lendingClerk.setGlobalPaused(true, false);
        assertEq(lendingClerk.globalBorrowPaused(), true);
        assertEq(lendingClerk.globalRepayPaused(), false);

        vm.expectEmit(address(lendingClerk));
        emit GlobalPausedSet(false, true);
        lendingClerk.setGlobalPaused(false, true);
        assertEq(lendingClerk.globalBorrowPaused(), false);
        assertEq(lendingClerk.globalRepayPaused(), true);
    }

    function test_setBorrowerPaused_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.setBorrowerPaused(address(borrower), true, true);
    }

    function test_setBorrowerPaused_success() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        vm.expectEmit(address(lendingClerk));
        emit BorrowerPausedSet(address(borrower), true, false);
        lendingClerk.setBorrowerPaused(address(borrower), true, false);
        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.borrowPaused, true);
        assertEq(details.repayPaused, false);

        vm.expectEmit(address(lendingClerk));
        emit BorrowerPausedSet(address(borrower), false, true);
        lendingClerk.setBorrowerPaused(address(borrower), false, true);
        details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, true);
    }

    function test_setGlobalInterestRateModel_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lendingClerk.setGlobalInterestRateModel(address(0));
    }

    function test_setGlobalInterestRateModel_success() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(lendingClerk));
        emit InterestRateModelUpdated(address(lendingClerk), alice);
        lendingClerk.setGlobalInterestRateModel(alice);
        assertEq(address(lendingClerk.globalInterestRateModel()), alice);
    }

    function test_addBorrower_fail_alreadyExisting() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.AlreadyEnabled.selector));
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);
    }

    function test_addBorrower_fail_badAddress() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lendingClerk.addBorrower(address(0), address(borrowerInterestRateModel), 100e6);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lendingClerk.addBorrower(address(borrower), address(0), 100e6);
    }

    function test_addBorrower_success() public {
        vm.startPrank(origamiMultisig);
        
        vm.expectEmit(address(lendingClerk));
        emit BorrowerAdded(
            address(borrower), 
            address(borrowerInterestRateModel), 
            "MockBorrower",
            "1.0.0"
        );
        emit DebtCeilingUpdated(
            address(borrower), 
            0, 
            100e6
        );
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(borrowerInterestRateModel));
        assertEq(details.debtCeiling, 100e6);

        address[] memory borrowersList = lendingClerk.borrowersList();
        assertEq(borrowersList.length, 1);
        assertEq(borrowersList[0], address(borrower));

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 0);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, 0);
    }

    function test_setBorrowerDebtCeiling_fail() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 123);
    }

    function test_setBorrowerDebtCeiling_success_noDebt() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        vm.expectEmit(address(lendingClerk));
        emit DebtCeilingUpdated(address(borrower), 100e6, 123);
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 123);

        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(borrowerInterestRateModel));
        assertEq(details.debtCeiling, 123);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 0);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, BORROWER_IR_AT_0_UR);
    }

    function test_setBorrowerDebtCeiling_success_withDebtBelow() public {
        // 90% UR - at kink
        doDeposit(1_000e6);
        doBorrow(1_000e18, 900e6);

        vm.warp(block.timestamp + 30 days);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 900e18);
        assertEq(debtPosition.interest, 11.164571697047772600e18);
        assertEq(debtPosition.interestDelta, 11.164571697047772600e18);
        assertEq(debtPosition.rate, BORROWER_IR_AT_KINK); // 15%

        // 45.5% UR after including the extra interest
        vm.expectEmit(address(lendingClerk));
        emit DebtCeilingUpdated(address(borrower), 1_000e18, 2_000e18);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), 0.125310126991584661e18); // A bit over 12.5%
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 2_000e18);

        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(borrowerInterestRateModel));
        assertEq(details.debtCeiling, 2_000e18);

        debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 900e18);
        assertEq(debtPosition.interest, 11.164571697047772600e18);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, 0.125310126991584661e18);
    }

    function test_setBorrowerDebtCeiling_success_withDebtAbove() public {
        // 90% UR - at kink
        doDeposit(1_000e6);
        doBorrow(1_000e18, 900e6);

        vm.warp(block.timestamp + 30 days);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 900e18);
        assertEq(debtPosition.interest, 11.164571697047772600e18);
        assertEq(debtPosition.interestDelta, 11.164571697047772600e18);
        assertEq(debtPosition.rate, BORROWER_IR_AT_KINK); // 15%

        // The debt ceiling is halved -- now at 200% UR
        vm.expectEmit(address(lendingClerk));
        emit DebtCeilingUpdated(address(borrower), 1_000e18, 450e18);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), BORROWER_IR_AT_100_UR);
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 450e18);

        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(borrowerInterestRateModel));
        assertEq(details.debtCeiling, 450e18);

        debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 900e18);
        assertEq(debtPosition.interest, 11.164571697047772600e18);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, BORROWER_IR_AT_100_UR); // 15% max IR
    }

    function test_setBorrowerInterestRateModel_fail_badModel() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lendingClerk.setBorrowerInterestRateModel(address(borrower), address(0));
    }

    function test_setBorrowerInterestRateModel_fail_noBorrower() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.setBorrowerInterestRateModel(address(borrower), address(borrowerInterestRateModel));
    }

    function test_setBorrowerInterestRateModel_success_noDebt() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 1_000e6);

        LinearWithKinkInterestRateModel newModel = new LinearWithKinkInterestRateModel(
            origamiMultisig,
            0.123e18,
            0.789e18,
            0.75e18,
            0.5e18
        );

        vm.warp(block.timestamp + 1 days);
        
        vm.expectEmit(address(lendingClerk));
        emit InterestRateModelUpdated(address(borrower), address(newModel));
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), 0.123e18);
        lendingClerk.setBorrowerInterestRateModel(address(borrower), address(newModel));
        
        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(newModel));
        assertEq(details.debtCeiling, 1_000e6);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 0);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, 0.123e18); // min IR
    }

    function test_setBorrowerInterestRateModel_success_withDebt() public {
        // 90% UR - at kink
        doDeposit(1_000e6);
        doBorrow(1_000e18, 900e6);

        LinearWithKinkInterestRateModel newModel = new LinearWithKinkInterestRateModel(
            origamiMultisig,
            0.123e18,
            0.789e18,
            0.75e18,
            0.5e18
        );

        uint96 expectedIr = 0.673827649511004098e18; // >90% UR, so close to the max

        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(address(lendingClerk));
        emit InterestRateModelUpdated(address(borrower), address(newModel));
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), expectedIr);
        lendingClerk.setBorrowerInterestRateModel(address(borrower), address(newModel));
        
        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(newModel));
        assertEq(details.debtCeiling, 1_000e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(borrower));
        assertEq(debtPosition.principal, 900e18);
        assertEq(debtPosition.interest, 0.369939023359945200e18); // 1 day of interest
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, expectedIr);
    }

    function test_setIdleStrategyInterestRate() public {
        vm.startPrank(origamiMultisig);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(idleStrategyManager), 0.0333e18);

        lendingClerk.setIdleStrategyInterestRate(0.0333e18);

        IOrigamiDebtToken.DebtorPosition memory debtPosition = iUsdc.getDebtorPosition(address(idleStrategyManager));
        assertEq(debtPosition.principal, 0);
        assertEq(debtPosition.interest, 0);
        assertEq(debtPosition.interestDelta, 0);
        assertEq(debtPosition.rate, 0.0333e18);
    }

    function test_shutdownBorrower_then_addBorrower() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        lendingClerk.shutdownBorrower(address(borrower));

        vm.expectEmit(address(lendingClerk));
        emit BorrowerAdded(
            address(borrower), 
            address(borrowerInterestRateModel), 
            "MockBorrower",
            "1.0.0"
        );
        emit DebtCeilingUpdated(
            address(borrower), 
            0, 
            100e6
        );
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 250e18);

        IOrigamiLendingClerk.BorrowerDetails memory details = lendingClerk.borrowerDetails(address(borrower));
        assertEq(details.name, "MockBorrower");
        assertEq(details.version, "1.0.0");
        assertEq(details.borrowPaused, false);
        assertEq(details.repayPaused, false);
        assertEq(details.interestRateModel, address(borrowerInterestRateModel));
        assertEq(details.debtCeiling, 250e18);

        address[] memory borrowersList = lendingClerk.borrowersList();
        assertEq(borrowersList.length, 1);
        assertEq(borrowersList[0], address(borrower));
    }

    function test_shutdownBorrower_fail_noBorrower() public {
        vm.startPrank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.shutdownBorrower(address(borrower));
    }

    function test_shutdownBorrower_success_zeroDebt() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);

        vm.expectEmit(address(lendingClerk));
        emit BorrowerShutdown(address(borrower), 0);
        lendingClerk.shutdownBorrower(address(borrower));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.borrowerDetails(address(borrower));
    }

    function test_shutdownBorrower_success_withDebt() public {
        doDeposit(1_000e6);
        doBorrow(100e18, 100e6);

        vm.expectEmit(address(lendingClerk));
        emit BorrowerShutdown(address(borrower), 100e18);
        lendingClerk.shutdownBorrower(address(borrower));

        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.borrowerDetails(address(borrower));
    }

    function test_refreshBorrowersInterestRate_fail_badBorrower() public {
        vm.startPrank(origamiMultisig);
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 1_000e6);

        address[] memory borrowers = new address[](2);
        (borrowers[0], borrowers[1]) = (address(borrower), alice);

        // Alice isn't a borrower
        vm.expectRevert(abi.encodeWithSelector(IOrigamiLendingClerk.BorrowerNotEnabled.selector));
        lendingClerk.refreshBorrowersInterestRate(borrowers);
    }

    function test_refreshBorrowersInterestRate_success_global() public {
        // supply 10k USDC, then borrower1 borrows 1k USDC @ 100% UR
        doDeposit(10_000e6);
        doBorrow(1_000e18, 1_000e6);

        // Add borrower 2, borrow 500 USDC @ 50% UR
        MockBorrower borrower2 = new MockBorrower(address(usdcToken), address(lendingClerk));
        lendingClerk.addBorrower(address(borrower2), address(borrowerInterestRateModel), 1_000e18);
        borrower2.borrow(500e6);

        // Ensure the checkpoint happens
        vm.warp(block.timestamp + 30 days);

        address[] memory borrowers = new address[](2);
        (borrowers[0], borrowers[1]) = (address(borrower), address(borrower2));

        vm.expectEmit(address(iUsdc));
        emit Checkpoint(address(idleStrategyManager), 10_000e18 - 1_000e18 - 500e18, 35.003382344037053e18);
        vm.expectEmit(address(iUsdc));
        emit Checkpoint(address(borrower), 1_000e18, 20.760507642263613e18);
        vm.expectEmit(address(iUsdc));
        emit Checkpoint(address(borrower2), 500e18, 5.2788128257917775e18);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower), BORROWER_IR_AT_100_UR);
        vm.expectEmit(address(iUsdc));
        emit InterestRateSet(address(borrower2), 0.128071045156988433e18);
        lendingClerk.refreshBorrowersInterestRate(borrowers);
    }

    function test_recoverToken() public {
        check_recoverToken(address(lendingClerk));
    }
}

contract OrigamiLendingClerkTestAccess is OrigamiLendingClerkTestBase {
    function test_access_setSupplyManager() public {
        expectElevatedAccess();
        lendingClerk.setSupplyManager(address(supplyManager));
    }

    function test_access_setGlobalPaused() public {
        expectElevatedAccess();
        lendingClerk.setGlobalPaused(true, true);
    }

    function test_access_setBorrowerPaused() public {
        expectElevatedAccess();
        lendingClerk.setBorrowerPaused(address(borrower), true, true);
    }

    function test_access_setGlobalInterestRateModel() public {
        expectElevatedAccess();
        lendingClerk.setGlobalInterestRateModel(address(globalInterestRateModel));
    }

    function test_access_addBorrower() public {
        expectElevatedAccess();
        lendingClerk.addBorrower(address(borrower), address(borrowerInterestRateModel), 100e6);
    }

    function test_access_setBorrowerDebtCeiling() public {
        expectElevatedAccess();
        lendingClerk.setBorrowerDebtCeiling(address(borrower), 100e6);
    }

    function test_access_setBorrowerInterestRateModel() public {
        expectElevatedAccess();
        lendingClerk.setBorrowerInterestRateModel(address(borrower), address(borrowerInterestRateModel));
    }

    function test_access_setIdleStrategyInterestRate() public {
        expectElevatedAccess();
        lendingClerk.setIdleStrategyInterestRate(0.1e18);
    }

    function test_access_shutdownBorrower() public {
        expectElevatedAccess();
        lendingClerk.shutdownBorrower(address(borrower));
    }

    function test_access_refreshBorrowersInterestRate() public {
        expectElevatedAccess();
        lendingClerk.refreshBorrowersInterestRate(new address[](1));
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        lendingClerk.recoverToken(address(usdcToken), alice, 100e6);
    }

    function test_access_deposit() public {
        expectElevatedAccess();
        lendingClerk.deposit(100e6);

        // Still doesn't work with the owner (only the supplyManager)
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        lendingClerk.deposit(100e6);
    }

    function test_access_withdraw() public {
        expectElevatedAccess();
        lendingClerk.withdraw(100e6, alice);

        // Still doesn't work with the owner (only the supplyManager)
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        lendingClerk.withdraw(100e6, alice);
    }

    function test_access_repay_fail() public {
        expectElevatedAccess();
        lendingClerk.repay(100e6, alice);
    }

    function test_access_repay_success_borrower() public {
        doDeposit(5_000_000e6);
        addBorrower(5_000_000e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(2_000_000e6, address(borrower));

        vm.startPrank(address(borrower));
        usdcToken.approve(address(lendingClerk), 100e6);
        lendingClerk.repay(100e6, address(borrower));
    }

    function test_access_repay_success_elevatedAccess() public {
        doDeposit(5_000_000e6);
        addBorrower(5_000_000e18);
        vm.startPrank(address(borrower));
        lendingClerk.borrow(2_000_000e6, origamiMultisig);

        vm.startPrank(origamiMultisig);
        usdcToken.approve(address(lendingClerk), 100e6);
        lendingClerk.repay(100e6, address(borrower));
    }
}
