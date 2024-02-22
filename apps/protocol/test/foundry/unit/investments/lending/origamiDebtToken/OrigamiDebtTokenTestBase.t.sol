pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { IOrigamiDebtToken, OrigamiDebtToken } from "contracts/investments/lending/OrigamiDebtToken.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { console2 } from "forge-std/Test.sol";

/* solhint-disable func-name-mixedcase, contract-name-camelcase, not-rely-on-time */
contract OrigamiDebtTokenTestBase is OrigamiTest {
    bool public constant LOG = false;

    OrigamiDebtToken public iUSDC;

    uint256 public constant TWO_PCT_1DAY = 100005479602179510500;
    uint256 public constant TWO_PCT_2DAY = 100010959504619421600;
    uint256 public constant TWO_PCT_365DAY = 102020134002675580900;
    uint256 public constant FIVE_PCT_1DAY = 100013699568442168900;
    uint256 public constant FIVE_PCT_364DAY = 105112709650002483400;
    uint256 public constant FIVE_PCT_365DAY = 105127109637602403900;
    uint256 public constant FIVE_PCT_729DAY = 110501953516812792800;

    // The net amount of base interest for 365 days, done in two steps (1 day, then 364 days)
    // There are very insignificant rounding diffs compared to doing it in one go as above
    uint256 public constant ONE_PCT_365DAY_ROUNDING = 101005016708416805542;

    // 10% 365 day cont. compounded interest on `ONE_PCT_365DAY_ROUNDING`
    uint256 public constant TEN_PCT_365DAY_1 = 112749685157937566936;

    event InterestRateSet(address indexed debtor, uint96 rate);
    event MinterSet(address indexed account, bool value);
    event DebtorBalance(address indexed debtor, uint128 principal, uint128 interest);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Checkpoint(address indexed debtor, uint128 principal, uint128 interest);

    function _setUp() internal {
        iUSDC = new OrigamiDebtToken("Origami iUSDC Debt", "iUSDC", origamiMultisig);
        vm.prank(origamiMultisig);
        iUSDC.setMinter(origamiMultisig, true);
    }

    /* solhint-disable no-console */
    function dumpBase() internal view {
        console2.log("TOTALS:", block.timestamp);

        IOrigamiDebtToken.DebtOwed memory debtOwed = iUSDC.currentTotalDebt();
        console2.log("principal:", debtOwed.principal);
        console2.log("interest:", debtOwed.interest);
        console2.log(".");
    }

    function dumpDebtor(address debtor) internal view {
        console2.log("DEBTOR: ", debtor);
        console2.log("block.timestamp:", block.timestamp);

        (uint128 principal, uint128 interestCheckpoint, uint32 timeCheckpoint, uint96 rate) = iUSDC.debtors(debtor);
        console2.log("rate:", rate);
        console2.log("principal:", principal);
        console2.log("interestCheckpoint:", interestCheckpoint);
        console2.log("timeCheckpoint:", timeCheckpoint);
        console2.log("balanceOf:", iUSDC.balanceOf(debtor));
        console2.log(".");
    }

    function checkTotals(
        uint256 expectedTotalPrincipal,
        uint256 expectedEstimatedInterest,
        uint256 expectedRepaidTotalInterest
    ) internal {
        if (LOG) dumpBase();

        IOrigamiDebtToken.DebtOwed memory debtOwed = iUSDC.currentTotalDebt();
        assertEq(debtOwed.principal, expectedTotalPrincipal, "totalPrincipal");
        assertEq(debtOwed.interest, expectedEstimatedInterest, "totalEstimatedInterest");

        assertEq(iUSDC.totalPrincipal(), debtOwed.principal, "totalPrincipal alt");
        assertEq(iUSDC.totalSupply(), expectedTotalPrincipal+expectedEstimatedInterest, "totalSupply");
        assertEq(iUSDC.estimatedTotalInterest(), expectedEstimatedInterest, "estimatedTotalInterest");
        assertEq(iUSDC.repaidTotalInterest(), expectedRepaidTotalInterest, "expectedRepaidTotalInterest");
        assertEq(iUSDC.estimatedCumulativeInterest(), expectedEstimatedInterest + expectedRepaidTotalInterest, "estimatedCumulativeInterest");
    }

    function checkDebtor(
        address debtor,
        uint256 expectedInterestRateBps, 
        uint256 expectedPrincipal,
        uint256 expectedInterestCheckpoint,
        uint256 expectedTimeCheckpoint,
        uint256 expectedBalancedOf
    ) internal {
        if (LOG) dumpDebtor(debtor);

        (uint128 principal, uint128 interestCheckpoint, uint32 timeCheckpoint, uint96 rate) = iUSDC.debtors(debtor);
        assertEq(rate, expectedInterestRateBps, "rate");
        assertEq(principal, expectedPrincipal, "principal");
        assertEq(interestCheckpoint, expectedInterestCheckpoint, "interestCheckpoint");
        assertEq(timeCheckpoint, expectedTimeCheckpoint, "timeCheckpoint");

        assertEq(iUSDC.balanceOf(debtor), expectedBalancedOf, "balanceOf");
    }

    function checkpointInterest(address debtor) internal {
        address[] memory _debtors = new address[](1);
        _debtors[0] = debtor;
        iUSDC.checkpointDebtorsInterest(_debtors);
    }

    function checkpointInterest(address debtor1, address debtor2) internal {
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (debtor1, debtor2);
        iUSDC.checkpointDebtorsInterest(_debtors);
    }

    function currentDebtsOf(address debtor1, address debtor2) internal view returns (
        IOrigamiDebtToken.DebtOwed memory, IOrigamiDebtToken.DebtOwed memory
    ) {
        address[] memory debtors = new address[](2);
        (debtors[0], debtors[1]) = (debtor1, debtor2);
        IOrigamiDebtToken.DebtOwed[] memory debts = iUSDC.currentDebtsOf(debtors);
        return (debts[0], debts[1]);
    }
}

contract OrigamiDebtTokenTestAdmin is OrigamiDebtTokenTestBase {
    function setUp() public {
        _setUp();
    }

    function test_initalization() public {
        assertEq(address(iUSDC.owner()), origamiMultisig);
        assertEq(iUSDC.name(), "Origami iUSDC Debt");
        assertEq(iUSDC.symbol(), "iUSDC");
        assertEq(iUSDC.decimals(), 18);
        assertEq(iUSDC.totalSupply(), 0);
        assertEq(iUSDC.totalPrincipal(), 0);
        assertEq(iUSDC.estimatedTotalInterest(), 0);
        assertEq(iUSDC.repaidTotalInterest(), 0);
        assertEq(iUSDC.estimatedCumulativeInterest(), 0);
    }

    function test_setMinter() public {
        vm.startPrank(origamiMultisig);
        assertEq(iUSDC.minters(alice), false);

        vm.expectEmit();
        emit MinterSet(alice, true);
        iUSDC.setMinter(alice, true);
        assertEq(iUSDC.minters(alice), true);

        vm.expectEmit();
        emit MinterSet(alice, false);
        iUSDC.setMinter(alice, false);
        assertEq(iUSDC.minters(alice), false);
    }

    function test_approve() public {
        vm.startPrank(bob);

        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        iUSDC.approve(alice, 100);

        assertEq(iUSDC.allowance(bob, alice), 0);
    }

    function test_recoverToken() public {
        check_recoverToken(address(iUSDC));
    }
}

contract OrigamiDebtTokenTestAccess is OrigamiDebtTokenTestBase {
    function setUp() public {
        _setUp();
    }

    function test_access_setMinter() public {
        expectElevatedAccess();
        iUSDC.setMinter(alice, true);
    }

    function test_access_setInterestRate() public {
        // Fails for Alice
        expectElevatedAccess();
        iUSDC.setInterestRate(alice, 0);

        // Works for elevated access
        vm.startPrank(origamiMultisig);
        iUSDC.setInterestRate(alice, 0);

        // Add alice as a minter - now succeeds.
        iUSDC.setMinter(alice, true);

        vm.startPrank(alice);
        iUSDC.setInterestRate(alice, 0);
    }

    function test_access_recoverToken() public {
        expectElevatedAccess();
        iUSDC.recoverToken(address(iUSDC), alice, 100);
    }

    function expectOnlyMinters() internal {
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
    }

    function test_access_mint() public {
        expectOnlyMinters();
        iUSDC.mint(alice, 100);
    }

    function test_access_burn() public {
        expectOnlyMinters();
        iUSDC.burn(alice, 100);
    }

    function test_access_burnAll() public {
        expectOnlyMinters();
        iUSDC.burnAll(alice);
    }

    function test_access_transfer() public {
        expectOnlyMinters();
        iUSDC.transfer(alice, 100);
    }

    function test_access_transferFrom() public {
        expectOnlyMinters();
        iUSDC.transferFrom(bob, alice, 100);
    }
}

contract OrigamiDebtTokenTestZeroInterest is OrigamiDebtTokenTestBase {
    uint96 internal constant ZERO_INTEREST = 0;

    function setUp() public {
        _setUp();
    }

    function test_mint_aliceAndBob_inDifferentBlock() public {
        vm.startPrank(origamiMultisig);
        uint256 amount = 100e18;
        iUSDC.mint(alice, amount);

        // Bob borrows 1 day later
        uint256 blockTs = block.timestamp;
        vm.warp(blockTs + 1 days);
        iUSDC.mint(bob, amount);

        // Just the amounts given zero interest
        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, 0, amount, 0, blockTs, amount);
        checkDebtor(bob, 0, amount, 0, block.timestamp, amount);

        vm.warp(block.timestamp + 364 days);
        address[] memory _debtors = new address[](2);
        (_debtors[0], _debtors[1]) = (alice, bob);
        iUSDC.checkpointDebtorsInterest(_debtors);

        // Just the amounts given zero interest
        checkTotals(2*amount, 0, 0);
        checkDebtor(alice, 0, amount, 0, block.timestamp, amount);
        checkDebtor(bob, 0, amount, 0, block.timestamp, amount);

        iUSDC.burn(bob, amount);
        iUSDC.burn(alice, amount);
        checkTotals(0, 0, 0);
        checkDebtor(alice, 0, 0, 0, block.timestamp, 0);
        checkDebtor(bob, 0, 0, 0, block.timestamp, 0);

    }
}
