pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

contract MockPausable is OrigamiManagerPausable {
    constructor(address _initialOwner) OrigamiElevatedAccess(_initialOwner) {}

    function getPaused() external view returns (Paused memory) {
        return _paused;
    }
}

contract OrigamiManagerPausableTest is OrigamiTest {
    MockPausable public pausable;

    event PauserSet(address indexed account, bool canPause);
    event PausedSet(IOrigamiManagerPausable.Paused paused);

    function setUp() public {
        pausable = new MockPausable(origamiMultisig);
    }

    function test_initialization() public {
        assertEq(pausable.owner(), origamiMultisig);
        IOrigamiManagerPausable.Paused memory paused = pausable.getPaused();
        assertEq(paused.investmentsPaused, false);
        assertEq(paused.exitsPaused, false);
        assertEq(pausable.isPauser(origamiMultisig), false);
    }

    function test_access_setPaused() public {
        vm.prank(origamiMultisig);
        vm.expectRevert(abi.encodeWithSelector(CommonEventsAndErrors.InvalidAccess.selector));
        pausable.setPaused(IOrigamiManagerPausable.Paused(true, true));

        expectElevatedAccess();
        pausable.setPaused(IOrigamiManagerPausable.Paused(true, true));
    }

    function test_access_setPauser() public {
        expectElevatedAccess();
        pausable.setPauser(alice, true);
    }

    function test_setPaused() public {
        vm.startPrank(origamiMultisig);
        pausable.setPauser(origamiMultisig, true);

        IOrigamiManagerPausable.Paused memory value = IOrigamiManagerPausable.Paused(true, true);
        emit PausedSet(value);
        pausable.setPaused(value);

        IOrigamiManagerPausable.Paused memory valueAfter = pausable.getPaused();
        assertEq(valueAfter.investmentsPaused, true);
        assertEq(valueAfter.exitsPaused, true);
    }

    function test_setPauser() public {
        vm.startPrank(origamiMultisig);

        emit PauserSet(alice, true);
        pausable.setPauser(alice, true);
        assertEq(pausable.isPauser(alice), true);

        emit PauserSet(alice, false);
        pausable.setPauser(alice, false);
        assertEq(pausable.isPauser(alice), false);
    }
}