pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/OrigamiMath.sol)

import { mulDiv as prbMulDiv } from "@prb/math/src/Common.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @notice Utilities to operate on fixed point math multipliation and division
 * taking rounding into consideration
 */
library OrigamiMath {
    enum Rounding {
        ROUND_DOWN,
        ROUND_UP
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10_000;

    function scaleUp(uint256 amount, uint256 scalar) internal pure returns (uint256) {
        // Special case for scalar == 1, as it's common for token amounts to not need
        // scaling if decimal places are the same
        return scalar == 1 ? amount : amount * scalar;
    }

    function scaleDown(
        uint256 amount, 
        uint256 scalar, 
        Rounding roundingMode
    ) internal pure returns (uint256 result) {
        // Special case for scalar == 1, as it's common for token amounts to not need
        // scaling if decimal places are the same
        if (scalar == 1) {
            result = amount;
        } else if (roundingMode == Rounding.ROUND_DOWN) {
            result = amount / scalar;
        } else {
            // ROUND_UP uses the same logic as OZ Math.ceilDiv()
            result = amount == 0 ? 0 : (amount - 1) / scalar + 1;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision,
     * rounding up
     */
    function mulDiv(
        uint256 x, 
        uint256 y, 
        uint256 denominator,
        Rounding roundingMode
    ) internal pure returns (uint256 result) {
        result = prbMulDiv(x, y, denominator);
        if (roundingMode == Rounding.ROUND_UP && mulmod(x, y, denominator) != 0) {
            result += 1;
        }
    }

    function subtractBps(uint256 inputAmount, uint256 basisPoints) internal pure returns (uint256 result) {
        uint256 numeratorBps;
        unchecked {
            numeratorBps = BASIS_POINTS_DIVISOR - basisPoints;
        }

        result = basisPoints < BASIS_POINTS_DIVISOR
            // Round down for min amounts out expected
            ? mulDiv(
                inputAmount,
                numeratorBps, 
                BASIS_POINTS_DIVISOR, 
                Rounding.ROUND_DOWN
            ) : 0;
    }

    function addBps(uint256 inputAmount, uint256 basisPoints) internal pure returns (uint256 result) {
        uint256 numeratorBps;
        unchecked {
            numeratorBps = BASIS_POINTS_DIVISOR + basisPoints;
        }

        // Round up for max amounts out expected
        result = mulDiv(
            inputAmount,
            numeratorBps, 
            BASIS_POINTS_DIVISOR, 
            Rounding.ROUND_UP
        );
    }

    /**
     * @notice Split the `inputAmount` into two parts based on the `basisPoints` fraction.
     * eg: 3333 BPS (33.3%) can be used to split an input amount of 600 into: (result=400, removed=200).
     * @dev In case of rounding, the `result` is rounded down, `removed` is rounded up
     */
    function splitSubtractBps(uint256 inputAmount, uint256 basisPoints) internal pure returns (uint256 result, uint256 removed) {
        result = subtractBps(inputAmount, basisPoints);
        unchecked {
            removed = inputAmount - result;
        }
    }

    /**
     * @notice Reverse the fractional amount of an input, rounding up.
     * eg: For 3333 BPS (33.3%) and the remainder=400, the result is 600
     * @dev Rounds up
     */
    function inverseSubtractBps(uint256 remainderAmount, uint256 basisPoints) internal pure returns (uint256 result) {
        if (basisPoints == 0) return remainderAmount; // gas shortcut for 0
        if (basisPoints >= BASIS_POINTS_DIVISOR) revert CommonEventsAndErrors.InvalidParam();

        uint256 denominatorBps;
        unchecked {
            denominatorBps = BASIS_POINTS_DIVISOR - basisPoints;
        }
        result = mulDiv(
            remainderAmount,
            BASIS_POINTS_DIVISOR, 
            denominatorBps, 
            OrigamiMath.Rounding.ROUND_UP
        );
    }
}
