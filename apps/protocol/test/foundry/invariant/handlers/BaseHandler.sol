pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Test } from "forge-std/Test.sol";
import { TimestampStore } from "test/foundry/invariant/stores/TimestampStore.sol";
import { StateStore } from "test/foundry/invariant/stores/StateStore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Base contract with common logic needed by all handler contracts.
abstract contract BaseHandler is Test {
    /// @dev Reference to the timestamp store, which is needed for simulating the passage of time.
    TimestampStore public timestampStore;

    /// @dev Reference which action has just run.
    StateStore public stateStore;

    /// @dev Maps function names to the number of times they have been called.
    mapping(bytes4 func => uint256 calls) public calls;

    /// @dev The total number of calls made to this contract.
    uint256 public totalCalls;

    constructor(TimestampStore timestampStore_, StateStore stateStore_) {
        timestampStore = timestampStore_;
        stateStore = stateStore_;
    }

    // Prank the given target sender
    modifier useSender() {
        vm.startPrank(msg.sender);
        _;
        vm.stopPrank();
    }

    /// @dev Simulates the passage of time. The time jump is upper bounded so that streams don't settle too quickly.
    /// See https://github.com/foundry-rs/foundry/issues/4994.
    /// @param timeJumpSeed A fuzzed value needed for generating random time warps.
    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 0, 40 days);
        timestampStore.increaseCurrentTimestamp(timeJump);
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    /// @dev Records a function call for instrumentation purposes, and also
    /// sets the state of the function which is running now
    modifier instrument() {
        calls[msg.sig]++;
        totalCalls++;
        stateStore.set(address(this), msg.sig);
        _;
    }

    function doMint(IERC20 token, address account, uint256 amount) internal {
        deal(address(token), account, token.balanceOf(account) + amount, true);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
