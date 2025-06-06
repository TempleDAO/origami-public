pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/SafeCast.sol)

/**
 * @notice A helper library for safe uint downcasting
 */
library SafeCast {
    error Overflow(uint256 amount);

    function encodeUInt128(uint256 amount) internal pure returns (uint128) {
        if (amount > type(uint128).max) {
            revert Overflow(amount);
        }
        return uint128(amount);
    }
    
    function encodeUInt112(uint256 amount) internal pure returns (uint112) {
        if (amount > type(uint112).max) {
            revert Overflow(amount);
        }
        return uint112(amount);
    }

    function encodeInt256(uint256 amount) internal pure returns (int256) {
        if (amount > uint256(type(int256).max)) {
            revert Overflow(amount);
        }
        return int256(amount);
    }
}
