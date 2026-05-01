pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";
import { OrigamiLanternOffering } from "contracts/periphery/OrigamiLanternOffering.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract OrigamiLanternOfferingTest is OrigamiTest {
    OrigamiLanternOffering internal lanternOffering;

    event Register(address indexed account, uint256 amount);
    event OfferingMade(address indexed account, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        lanternOffering = new OrigamiLanternOffering(origamiMultisig);
    }

    function buildRegistrations(uint256 num) private view returns (bytes32[] memory data) {
        OrigamiLanternOffering.Registration[] memory registrations = new OrigamiLanternOffering.Registration[](num);
        uint256 x;
        for (uint256 i = 0; i < num; ++i) {
            x = i+1;
            registrations[i].account = address(uint160(x));
            registrations[i].amount = uint96(x * 1e18);
        }
        data = lanternOffering.batchRegisterInputs(registrations);
    }

    function test_batchRegisterInputs() public view {
        // Empty array
        OrigamiLanternOffering.Registration[] memory registrations;
        bytes32[] memory data = lanternOffering.batchRegisterInputs(registrations);
        assertEq(data.length, 0);

        // uninitialized item - not checked
        registrations = new OrigamiLanternOffering.Registration[](1);
        data = lanternOffering.batchRegisterInputs(registrations);
        assertEq(data.length, 1);
        assertEq(data[0], bytes32(0));

        // 1 correct item
        data = buildRegistrations(1);
        assertEq(data.length, 1);
        assertEq(data[0], 0x0000000000000000000000000000000000000001000000000de0b6b3a7640000);

        // 5 correct items
        data = buildRegistrations(5);
        assertEq(data.length, 5);
        assertEq(data[0], 0x0000000000000000000000000000000000000001000000000de0b6b3a7640000);
        assertEq(data[1], 0x0000000000000000000000000000000000000002000000001bc16d674ec80000);
        assertEq(data[2], 0x00000000000000000000000000000000000000030000000029a2241af62c0000);
        assertEq(data[3], 0x0000000000000000000000000000000000000004000000003782dace9d900000);
        assertEq(data[4], 0x0000000000000000000000000000000000000005000000004563918244f40000);
    }

    function test_batchRegister_access() public {
        expectElevatedAccess();
        lanternOffering.batchRegister(new bytes32[](0));
    }

    function test_batchRegister_revertZeroAddress() public {
        vm.startPrank(origamiMultisig);

        OrigamiLanternOffering.Registration[] memory registrations = new OrigamiLanternOffering.Registration[](1);
        registrations[0].account = address(0);
        registrations[0].amount = 123;

        bytes32[] memory data = lanternOffering.batchRegisterInputs(registrations);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAddress.selector, address(0)));
        lanternOffering.batchRegister(data);
    }

    function test_batchRegister_revertZeroAmount() public {
        vm.startPrank(origamiMultisig);

        OrigamiLanternOffering.Registration[] memory registrations = new OrigamiLanternOffering.Registration[](1);
        registrations[0].account = address(123);
        registrations[0].amount = 0;

        bytes32[] memory data = lanternOffering.batchRegisterInputs(registrations);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.ExpectedNonZero.selector));
        lanternOffering.batchRegister(data);
    }

    function test_batchRegister_revertAlreadyRegistered() public {
        vm.startPrank(origamiMultisig);
        
        bytes32[] memory data = buildRegistrations(1);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(1), 1e18);
        lanternOffering.batchRegister(data);

        vm.expectRevert(abi.encodeWithSelector(OrigamiLanternOffering.AlreadyRegistered.selector));
        lanternOffering.batchRegister(data);
    }

    function test_batchRegister_success_one() public {
        vm.startPrank(origamiMultisig);

        bytes32[] memory data = buildRegistrations(1);

        vm.expectEmit(address(lanternOffering));
        emit Register(address(1), 1e18);
        lanternOffering.batchRegister(data);

        assertEq(lanternOffering.totalSupply(), 1e18);
        assertEq(lanternOffering.balanceOf(address(1)), 1e18);
        assertFalse(lanternOffering.participatedInOffering(address(1)));
        assertEq(lanternOffering.totalOffered(), 0);
    }

    function test_batchRegister_success_five() public {
        vm.startPrank(origamiMultisig);

        bytes32[] memory data = buildRegistrations(5);

        vm.expectEmit(address(lanternOffering));
        emit Register(address(1), 1e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(2), 2e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(3), 3e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(4), 4e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(5), 5e18);
        lanternOffering.batchRegister(data);

        assertEq(lanternOffering.totalSupply(), 15e18);
        assertEq(lanternOffering.balanceOf(address(3)), 3e18); // check one of them
        assertFalse(lanternOffering.participatedInOffering(address(3)));
        assertEq(lanternOffering.totalOffered(), 0);
    }

    function test_batchRegister_success_split() public {
        vm.startPrank(origamiMultisig);

        bytes32[] memory data = buildRegistrations(5);
        bytes32[] memory data1 = new bytes32[](3);
        bytes32[] memory data2 = new bytes32[](2);
        data1[0] = data[0];
        data1[1] = data[1];
        data1[2] = data[2];
        data2[0] = data[3];
        data2[1] = data[4];

        vm.expectEmit(address(lanternOffering));
        emit Register(address(1), 1e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(2), 2e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(3), 3e18);
        lanternOffering.batchRegister(data1);

        assertEq(lanternOffering.totalSupply(), 6e18);
        assertEq(lanternOffering.balanceOf(address(3)), 3e18); // check one of them
        assertFalse(lanternOffering.participatedInOffering(address(3)));
        assertEq(lanternOffering.totalOffered(), 0);

        vm.expectEmit(address(lanternOffering));
        emit Register(address(4), 4e18);
        vm.expectEmit(address(lanternOffering));
        emit Register(address(5), 5e18);
        lanternOffering.batchRegister(data2);

        assertEq(lanternOffering.totalSupply(), 15e18);
        assertEq(lanternOffering.balanceOf(address(5)), 5e18); // check one of them
        assertFalse(lanternOffering.participatedInOffering(address(5)));
        assertEq(lanternOffering.totalOffered(), 0);
    }

    function test_batchRegister_gas() public {
        vm.startPrank(origamiMultisig);

        uint256 gasBefore = gasleft();
        uint256 gasAfter;
        bytes32[] memory data = buildRegistrations(100);
        lanternOffering.batchRegister(data);
        gasAfter = gasleft();
        assertLt(gasBefore-gasAfter, 2_850_000);
    }

    function test_participateInOffering_revertPaused() public {
        vm.startPrank(alice);
        vm.expectRevert("Pausable: paused");
        lanternOffering.participateInOffering();
    }

    function test_participateInOffering_revertNotRegistered() public {
        vm.startPrank(origamiMultisig);
        lanternOffering.togglePauseOffering();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OrigamiLanternOffering.NotRegistered.selector));
        lanternOffering.participateInOffering();
    }

    function test_participateInOffering_revertAlreadyParticipating() public {
        vm.startPrank(origamiMultisig);
        lanternOffering.batchRegister(buildRegistrations(1));
        lanternOffering.togglePauseOffering();

        vm.startPrank(address(1));
        lanternOffering.participateInOffering();

        vm.expectRevert(abi.encodeWithSelector(OrigamiLanternOffering.AlreadyParticipating.selector));
        lanternOffering.participateInOffering();
    }

    function test_participateInOffering_success_one() public {
        vm.startPrank(origamiMultisig);
        lanternOffering.batchRegister(buildRegistrations(1));
        lanternOffering.togglePauseOffering();

        vm.startPrank(address(1));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(1), 1e18);
        lanternOffering.participateInOffering();

        assertEq(lanternOffering.totalSupply(), 1e18);
        assertEq(lanternOffering.balanceOf(address(1)), 1e18);
        assertTrue(lanternOffering.participatedInOffering(address(1)));
        assertEq(lanternOffering.totalOffered(), 1e18);
    }

    function test_participateInOffering_success_partialFive() public {
        vm.startPrank(origamiMultisig);
        lanternOffering.batchRegister(buildRegistrations(5));
        lanternOffering.togglePauseOffering();

        vm.startPrank(address(1));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(1), 1e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(3));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(3), 3e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(4));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(4), 4e18);
        lanternOffering.participateInOffering();

        assertEq(lanternOffering.totalSupply(), 15e18);
        assertEq(lanternOffering.balanceOf(address(4)), 4e18);
        assertTrue(lanternOffering.participatedInOffering(address(4)));
        assertEq(lanternOffering.totalOffered(), 8e18);
    }

    function test_participateInOffering_success_allFive() public {
        vm.startPrank(origamiMultisig);
        lanternOffering.batchRegister(buildRegistrations(5));
        lanternOffering.togglePauseOffering();

        vm.startPrank(address(1));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(1), 1e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(2));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(2), 2e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(3));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(3), 3e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(4));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(4), 4e18);
        lanternOffering.participateInOffering();

        vm.startPrank(address(5));
        vm.expectEmit(address(lanternOffering));
        emit OfferingMade(address(5), 5e18);
        lanternOffering.participateInOffering();

        assertEq(lanternOffering.totalSupply(), 15e18);
        assertEq(lanternOffering.balanceOf(address(5)), 5e18);
        assertTrue(lanternOffering.participatedInOffering(address(5)));
        assertEq(lanternOffering.totalOffered(), 15e18);
    }

    function test_togglePauseOffering_access() public {
        expectElevatedAccess();
        lanternOffering.togglePauseOffering();
    }

    function test_togglePauseOffering() public {
        vm.startPrank(origamiMultisig);
        vm.assertTrue(lanternOffering.paused());

        vm.expectEmit(address(lanternOffering));
        emit Unpaused(origamiMultisig);
        lanternOffering.togglePauseOffering();
        vm.assertFalse(lanternOffering.paused());

        vm.expectEmit(address(lanternOffering));
        emit Paused(origamiMultisig);
        lanternOffering.togglePauseOffering();
        vm.assertTrue(lanternOffering.paused());
    }
}
