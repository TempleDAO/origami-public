pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/Range.sol)

/**
 * @notice A helper library to track a valid range from floor <= x <= ceiling
 */
library Range {
    error InvalidRange(uint128 floor, uint128 ceiling);

    struct Data {
        uint128 floor;
        uint128 ceiling;
    }

    function set(Data storage range, uint128 floor, uint128 ceiling) internal {
        if (floor > ceiling) {
            revert InvalidRange(floor, ceiling);
        }
        range.floor = floor;
        range.ceiling = ceiling;
    }
}
