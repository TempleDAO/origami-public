pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { TimestampStore } from "test/foundry/invariant/stores/TimestampStore.sol";
import { StateStore } from "test/foundry/invariant/stores/StateStore.sol";
import { OrigamiTest } from "test/foundry/OrigamiTest.sol";

/// @notice Common logic needed by all invariant tests.
abstract contract BaseInvariantTest is StdInvariant, OrigamiTest {
    TimestampStore internal timestampStore;
    StateStore internal stateStore;

    modifier useCurrentTimestamp() {
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    function setUp() public virtual {
        timestampStore = new TimestampStore();
        vm.label({ account: address(timestampStore), newLabel: "TimestampStore" });
        excludeSender(address(timestampStore));
        
        stateStore = new StateStore();
        vm.label({ account: address(stateStore), newLabel: "StateStore" });
        excludeSender(address(stateStore));
    }

    function mkArray(bytes4 i1, bytes4 i2) internal pure returns (bytes4[] memory arr) {
        arr = new bytes4[](2);
        (arr[0], arr[1]) = (i1, i2);
    }

    function mkArray(bytes4 i1, bytes4 i2, bytes4 i3, bytes4 i4) internal pure returns (bytes4[] memory arr) {
        arr = new bytes4[](4);
        (arr[0], arr[1], arr[2], arr[3]) = (i1, i2, i3, i4);
    }

    function targetSelectors(address addr, bytes4[] memory fnSelectors) internal {
        targetContract(addr);
        targetSelector(
            StdInvariant.FuzzSelector({
                addr: addr, 
                selectors: fnSelectors
            })
        );
    }
}
