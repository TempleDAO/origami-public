pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OlympusCoolerDelegation } from "contracts/libraries/OlympusCoolerDelegation.sol";
import { OlympusMonoCoolerDeployerLib } from "test/foundry/unit/investments/olympus/OlympusMonoCoolerDeployerLib.m.sol";
import { DLGTEv1 } from "contracts/test/external/olympus/src/modules/DLGTE/DLGTE.v1.sol";
import { MonoCooler } from "contracts/test/external/olympus/src/policies/cooler/MonoCooler.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { IDLGTEv1 } from "contracts/interfaces/external/olympus/IDLGTE.v1.sol";

contract CoolerUserMock {
    using SafeERC20 for IERC20;

    MonoCooler internal cooler;
    IERC20 internal gohm;

    mapping(address account => OlympusCoolerDelegation.Data delegation) public delegations;

    constructor(MonoCooler cooler_, IERC20 gohm_) {
        cooler = cooler_;
        gohm = gohm_;
        gohm.safeIncreaseAllowance(address(cooler), type(uint256).max);
    }

    function addCollateral(
        uint128 amount
    ) external {
        cooler.addCollateral(amount, address(this), new DLGTEv1.DelegationRequest[](0));
    }
    
    function _applyDelegations(IDLGTEv1.DelegationRequest[] memory requests) private {
        if (requests.length > 0) {
            cooler.applyDelegations(requests, address(this));
        }
    }

    function updateDelegateAndAmount(
        address account,
        address newDelegateAddress,
        uint256 newAmount
    ) external returns (IDLGTEv1.DelegationRequest[] memory requests) {
        requests = OlympusCoolerDelegation.updateDelegateAndAmount(
            delegations[account],
            account,
            newDelegateAddress,
            newAmount
        );
        _applyDelegations(requests);
    }

    function syncAccountAmount1(
        address account,
        uint256 accountNewAmount
    ) external returns (IDLGTEv1.DelegationRequest[] memory requests) {
        requests = OlympusCoolerDelegation.syncAccountAmount(
            delegations[account],
            account,
            accountNewAmount
        );
        _applyDelegations(requests);
    }

    function syncAccountAmount2(
        address account1,
        uint256 account1NewAmount,
        address account2,
        uint256 account2NewAmount
    ) external returns (IDLGTEv1.DelegationRequest[] memory requests) {
        requests = OlympusCoolerDelegation.syncAccountAmount(
            delegations[account1],
            account1,
            account1NewAmount,
            delegations[account2],
            account2,
            account2NewAmount
        );
        _applyDelegations(requests);
    }
}

contract OlympusCoolerDelegationTestBase is OrigamiTest {
    address internal immutable OTHERS = makeAddr("OTHERS");

    CoolerUserMock internal coolerUserMock;
    DLGTEv1 internal DLGTE;
    MonoCooler internal cooler;

    event DelegationApplied(address indexed account, address indexed delegate, int256 amount);

    uint128 internal constant ADDED_COLLATERAL = 100_000e18;

    function setUp() public {
        OlympusMonoCoolerDeployerLib.Contracts memory deployedContracts;

        OlympusMonoCoolerDeployerLib.deploy(deployedContracts, bytes32(0), origamiMultisig, OTHERS);
        DLGTE = deployedContracts.DLGTE;
        cooler = deployedContracts.monoCooler;

        coolerUserMock = new CoolerUserMock(cooler, deployedContracts.gOHM);
        deployedContracts.gOHM.mint(address(coolerUserMock), ADDED_COLLATERAL);
        coolerUserMock.addCollateral(ADDED_COLLATERAL);
    }

    function checkDelegation(address account, address expectedDelegate, uint256 expectedAmount) internal view {
        (address delegateAddress, uint256 delegatedAmount) = coolerUserMock.delegations(account);
        assertEq(delegateAddress, expectedDelegate, "delegations::delegateAddress");
        assertEq(delegatedAmount, expectedAmount, "delegations::amount");
    }

    function checkTotalDelegated(
        uint256 expectedTotalGOhm,
        uint256 expectedDelegatedGOhm,
        uint256 expectedNumDelegateAddresses,
        uint256 expectedMaxAllowedDelegateAddresses
    ) internal view {
        (
            uint256 totalGOhm,
            uint256 delegatedGOhm,
            uint256 numDelegateAddresses,
            uint256 maxAllowedDelegateAddresses
        ) = DLGTE.accountDelegationSummary(address(coolerUserMock));
        assertEq(totalGOhm, expectedTotalGOhm, "DLGTE.accountDelegationSummary::totalGOhm");
        assertEq(delegatedGOhm, expectedDelegatedGOhm, "DLGTE.accountDelegationSummary::delegatedGOhm");
        assertEq(numDelegateAddresses, expectedNumDelegateAddresses, "DLGTE.accountDelegationSummary::numDelegateAddresses");
        assertEq(maxAllowedDelegateAddresses, expectedMaxAllowedDelegateAddresses, "DLGTE.accountDelegationSummary::maxAllowedDelegateAddresses");
    }

    function checkDelegations0() internal view {
        DLGTEv1.AccountDelegation[] memory delegations = DLGTE.accountDelegationsList(
            address(coolerUserMock), 0, 10
        );
        assertEq(delegations.length, 0, "DLGTE.accountDelegationsList::length");
    }

    function checkDelegations1(address delegate, uint256 amount) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = DLGTE.accountDelegationsList(
            address(coolerUserMock), 0, 10
        );
        assertEq(delegations.length, 1, "DLGTE.accountDelegationsList::length");
        if (delegations.length > 0) {
            assertEq(delegations[0].delegate, delegate, "DLGTE.accountDelegationsList::delegate");
            assertNotEq(delegations[0].escrow, address(0), "DLGTE.accountDelegationsList::escrow");
            assertEq(delegations[0].amount, amount, "DLGTE.accountDelegationsList::amount");
        }
    }

    function checkDelegations2(
        address delegate1, uint256 amount1,
        address delegate2, uint256 amount2
    ) internal view {
        DLGTEv1.AccountDelegation[] memory delegations = DLGTE.accountDelegationsList(
            address(coolerUserMock), 0, 10
        );
        if (delegations.length > 0) {
            assertEq(delegations.length, 2, "DLGTE.accountDelegationsList::length");
            assertEq(delegations[0].delegate, delegate1, "DLGTE.accountDelegationsList::delegate1");
            assertNotEq(delegations[0].escrow, address(0), "DLGTE.accountDelegationsList::escrow1");
            assertEq(delegations[0].amount, amount1, "DLGTE.accountDelegationsList::amount1");
        }
        if (delegations.length > 1) {
            assertEq(delegations[1].delegate, delegate2, "DLGTE.accountDelegationsList::delegate2");
            assertNotEq(delegations[1].escrow, delegations[0].escrow, "DLGTE.accountDelegationsList::escrow2");
            assertNotEq(delegations[1].escrow, address(0), "DLGTE.accountDelegationsList::escrow2");
            assertEq(delegations[1].amount, amount2, "DLGTE.accountDelegationsList::amount2");
        }            
    }

    function checkEmpty(IDLGTEv1.DelegationRequest[] memory req) internal pure {
        assertEq(req.length, 0);
    }

    function checkOne(
        IDLGTEv1.DelegationRequest[] memory req,
        address expectedDelegate,
        int256 expectedAmount
    ) internal pure {
        assertEq(req.length, 1);
        assertEq(req[0].delegate, expectedDelegate);
        assertEq(req[0].amount, expectedAmount);
    }

    function checkTwo(
        IDLGTEv1.DelegationRequest[] memory req,
        address expectedDelegate1,
        int256 expectedAmount1,
        address expectedDelegate2,
        int256 expectedAmount2
    ) internal pure {
        assertEq(req.length, 2);
        assertEq(req[0].delegate, expectedDelegate1);
        assertEq(req[0].amount, expectedAmount1);
        assertEq(req[1].delegate, expectedDelegate2);
        assertEq(req[1].amount, expectedAmount2);
    }
}

contract OlympusCoolerDelegationTest_updateDelegateAndAmount is OlympusCoolerDelegationTestBase {
    function test_updateDelegateAndAmount_fail_zeroAccount() public {
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(address(0), alice, 100);
        checkEmpty(req);
    }

    function test_updateDelegateAndAmount_newDelegate_fromNone_zeroAmount() public {
        uint256 delegateAmount = 0;

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        checkEmpty(req);
        checkDelegation(alice, alice, delegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, delegateAmount, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_newDelegate_fromNone_someAmount() public {
        uint256 delegateAmount = 100e18;

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        checkOne(req, alice, int256(delegateAmount));
        checkDelegation(alice, alice, delegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, delegateAmount, 1, 10);
        checkDelegations1(alice, delegateAmount);
    }

    function test_updateDelegateAndAmount_newDelegate_fromExisting_sameAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = delegateAmount;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, bob, int256(newDelegateAmount));
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, bob, newDelegateAmount);

        checkTwo(req, alice, -int256(delegateAmount), bob, int256(newDelegateAmount));
        checkDelegation(alice, bob, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(bob, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_newDelegate_fromExisting_increasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 333e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, bob, int256(newDelegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, bob, newDelegateAmount);

        checkTwo(req, alice, -int256(delegateAmount), bob, int256(newDelegateAmount));
        checkDelegation(alice, bob, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(bob, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_newDelegate_fromExisting_decreasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 69e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, bob, int256(newDelegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, bob, newDelegateAmount);

        checkTwo(req, alice, -int256(delegateAmount), bob, int256(newDelegateAmount));
        checkDelegation(alice, bob, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(bob, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_newDelegate_fromExisting_zeroAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 0;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, bob, newDelegateAmount);
        
        checkOne(req, alice, -int256(delegateAmount));
        checkDelegation(alice, bob, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_existingDelegate_sameAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = delegateAmount;
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, newDelegateAmount);

        checkEmpty(req);
        checkDelegation(alice, alice, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(alice, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_existingDelegate_increasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 333e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, int256(newDelegateAmount)-int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, newDelegateAmount);
        
        checkOne(req, alice, int256(newDelegateAmount)-int256(delegateAmount));
        checkDelegation(alice, alice, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(alice, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_existingDelegate_decreasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 69e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, int256(newDelegateAmount)-int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, newDelegateAmount);

        checkOne(req, alice, int256(newDelegateAmount)-int256(delegateAmount));
        checkDelegation(alice, alice, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 1, 10);
        checkDelegations1(alice, newDelegateAmount);
    }

    function test_updateDelegateAndAmount_existingDelegate_zeroAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 0;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, int256(newDelegateAmount)-int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, alice, newDelegateAmount);

        checkOne(req, alice, int256(newDelegateAmount)-int256(delegateAmount));
        checkDelegation(alice, alice, newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromNone_zeroAmount() public {
        uint256 newDelegateAmount = 0;
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkEmpty(req);
        checkDelegation(alice, address(0), newDelegateAmount);
        checkTotalDelegated(ADDED_COLLATERAL, newDelegateAmount, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromNone_someAmount() public {
        uint256 newDelegateAmount = 69e18;
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkEmpty(req);
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromExisting_sameAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = delegateAmount;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkOne(req, alice, -int256(delegateAmount));
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromExisting_increasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 333e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkOne(req, alice, -int256(delegateAmount));
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromExisting_decreasedAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 69e18;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkOne(req, alice, -int256(delegateAmount));
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }

    function test_updateDelegateAndAmount_removeDelegate_fromExisting_zeroAmount() public {
        uint256 delegateAmount = 100e18;
        coolerUserMock.updateDelegateAndAmount(alice, alice, delegateAmount);

        uint256 newDelegateAmount = 0;
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -int256(delegateAmount));
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.updateDelegateAndAmount(alice, address(0), newDelegateAmount);

        checkOne(req, alice, -int256(delegateAmount));
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }
}

contract OlympusCoolerDelegationtest_syncAccountAmount1 is OlympusCoolerDelegationTestBase {
    function test_syncAccountAmount1_fail_zeroAccount() public {
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(address(0), 100);
        checkEmpty(req);
    }

    function test_syncAccountAmount1_noAccountDelegate() public {
        coolerUserMock.updateDelegateAndAmount(alice, address(0), 0);

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 100e18);

        checkEmpty(req);
        checkDelegation(alice, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }

    function test_syncAccountAmount1_noAccountDelegateAmount() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 0);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 100e18);

        checkOne(req, alice, int256(100e18));
        checkDelegation(alice, alice, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(
            alice, 100e18
        );
    }

    function test_syncAccountAmount1_sameAccount1() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 100e18);

        checkEmpty(req);
        checkDelegation(alice, alice, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(alice, 100e18);
    }

    function test_syncAccountAmount1_increaseAccount1() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 200e18);

        checkOne(req, alice, 100e18);
        checkDelegation(alice, alice, 200e18);
        checkTotalDelegated(ADDED_COLLATERAL, 200e18, 1, 10);
        checkDelegations1(
            alice, 200e18
        );
    }

    function test_syncAccountAmount1_decreaseAccount1() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -50e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 50e18);

        checkOne(req, alice, -50e18);
        checkDelegation(alice, alice, 50e18);
        checkTotalDelegated(ADDED_COLLATERAL, 50e18, 1, 10);
        checkDelegations1(
            alice, 50e18
        );
    }

    function test_syncAccountAmount1_toZeroAccount() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount1(alice, 0);

        checkOne(req, alice, -100e18);
        checkDelegation(alice, alice, 0);
        checkTotalDelegated(ADDED_COLLATERAL, 0, 0, 10);
        checkDelegations0();
    }
}

contract OlympusCoolerDelegationtest_syncAccountAmount2 is OlympusCoolerDelegationTestBase {
    function test_syncAccountAmount2_fail_sameAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(alice)));
        coolerUserMock.syncAccountAmount2(alice, 100, alice, 100);
    }

    function test_syncAccountAmount2_fail_zeroAccount1() public {
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(address(0), 100, alice, 100);
        checkEmpty(req);
    }

    function test_syncAccountAmount2_fail_zeroAccount2() public {
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100, address(0), 100);
        checkEmpty(req);
    }

    function test_syncAccountAmount2_noAccount1Delegate_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, address(0), 0);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 100e18);

        checkEmpty(req);
        checkDelegation(alice, address(0), 0);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(bob, 100e18);
    }

    function test_syncAccountAmount2_noAccount1DelegateAmount_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 0);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 100e18);

        checkOne(req, alice, 100e18);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 200e18, 2, 10);
        checkDelegations2(
            bob, 100e18,
            alice, 100e18
        );
    }

    function test_syncAccountAmount2_sameAccount1_noAccount2Delegate() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, address(0), 0);

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 100e18);

        checkEmpty(req);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, address(0), 0);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(alice, 100e18);
    }

    function test_syncAccountAmount2_sameAccount1_noAccount2DelegateAmount() public {
        coolerUserMock.updateDelegateAndAmount(alice, bob, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 0);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 100e18);

        checkOne(req, bob, 100e18);
        checkDelegation(alice, bob, 100e18);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 200e18, 1, 10);
        checkDelegations1(
            bob, 200e18
        );
    }

    function test_syncAccountAmount2_sameAccount1_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 0);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 100e18);

        checkEmpty(req);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 200e18, 2, 10);
        checkDelegations2(
            alice, 100e18,
            bob, 100e18
        );
    }

    function test_syncAccountAmount2_increaseAccount1_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 200e18, bob, 100e18);

        checkOne(req, alice, 100e18);
        checkDelegation(alice, alice, 200e18);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 300e18, 2, 10);
        checkDelegations2(
            alice, 200e18,
            bob, 100e18
        );
    }

    function test_syncAccountAmount2_decreaseAccount1_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -50e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 50e18, bob, 100e18);

        checkOne(req, alice, -50e18);
        checkDelegation(alice, alice, 50e18);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 150e18, 2, 10);
        checkDelegations2(
            alice, 50e18,
            bob, 100e18
        );
    }

    function test_syncAccountAmount2_sameAccount1_increaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 200e18);

        checkOne(req, bob, 100e18);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, bob, 200e18);
        checkTotalDelegated(ADDED_COLLATERAL, 300e18, 2, 10);
        checkDelegations2(
            alice, 100e18,
            bob, 200e18
        );
    }

    function test_syncAccountAmount2_increaseAccount1_increaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 200e18, bob, 200e18);
        
        checkTwo(req, alice, 100e18, bob, 100e18);
        checkDelegation(alice, alice, 200e18);
        checkDelegation(bob, bob, 200e18);
        checkTotalDelegated(ADDED_COLLATERAL, 400e18, 2, 10);
        checkDelegations2(
            alice, 200e18,
            bob, 200e18
        );
    }

    function test_syncAccountAmount2_decreaseAccount1_increaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -50e18);
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, 100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 50e18, bob, 200e18);

        checkTwo(req, alice, -50e18, bob, 100e18);
        checkDelegation(alice, alice, 50e18);
        checkDelegation(bob, bob, 200e18);
        checkTotalDelegated(ADDED_COLLATERAL, 250e18, 2, 10);
        checkDelegations2(
            alice, 50e18,
            bob, 200e18
        );
    }

    function test_syncAccountAmount2_sameAccount1_decreaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, -50e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 50e18);

        checkOne(req, bob, -50e18);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, bob, 50e18);
        checkTotalDelegated(ADDED_COLLATERAL, 150e18, 2, 10);
        checkDelegations2(
            alice, 100e18,
            bob, 50e18
        );
    }

    function test_syncAccountAmount2_increaseAccount1_decreaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, 100e18);
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, -50e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 200e18, bob, 50e18);

        checkTwo(req, alice, 100e18, bob, -50e18);
        checkDelegation(alice, alice, 200e18);
        checkDelegation(bob, bob, 50e18);
        checkTotalDelegated(ADDED_COLLATERAL, 250e18, 2, 10);
        checkDelegations2(
            alice, 200e18,
            bob, 50e18
        );
    }

    function test_syncAccountAmount2_decreaseAccount1_decreaseAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -50e18);
        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, -50e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 50e18, bob, 50e18);

        checkTwo(req, alice, -50e18, bob, -50e18);
        checkDelegation(alice, alice, 50e18);
        checkDelegation(bob, bob, 50e18);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 2, 10);
        checkDelegations2(
            alice, 50e18,
            bob, 50e18
        );
    }

    function test_syncAccountAmount2_sameAccount1_toZeroAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(bob, bob, -100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 100e18, bob, 0);

        checkOne(req, bob, -100e18);
        checkDelegation(alice, alice, 100e18);
        checkDelegation(bob, bob, 0);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(
            alice, 100e18
        );
    }

    function test_syncAccountAmount2_toZeroAccount1_sameAccount2() public {
        coolerUserMock.updateDelegateAndAmount(alice, alice, 100e18);
        coolerUserMock.updateDelegateAndAmount(bob, bob, 100e18);

        vm.expectEmit(address(coolerUserMock));
        emit DelegationApplied(alice, alice, -100e18);
        vm.expectCall(address(cooler), abi.encodeWithSelector(MonoCooler.applyDelegations.selector), 1);
        IDLGTEv1.DelegationRequest[] memory req = coolerUserMock.syncAccountAmount2(alice, 0, bob, 100e18);

        checkOne(req, alice, -100e18);
        checkDelegation(alice, alice, 0);
        checkDelegation(bob, bob, 100e18);
        checkTotalDelegated(ADDED_COLLATERAL, 100e18, 1, 10);
        checkDelegations1(
            bob, 100e18
        );
    }
}
