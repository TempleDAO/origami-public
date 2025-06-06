// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

// AmountCapLib.sol taken from the following commit:
//  https://github.com/euler-xyz/euler-vault-kit/commit/3d9120ecd8f8725f370c8a13598e0e09a454d5f7

// The following declaration was not part of this original file, 
// instead it was imported from another file with `import {AmountCap} from "./Types.sol";`
// For simplicity, it was included in this snippet.
type AmountCap is uint16;

/// @title AmountCapLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `AmountCap` custom type
/// @dev AmountCaps are 16-bit decimal floating point values:
/// * The least significant 6 bits are the exponent
/// * The most significant 10 bits are the mantissa, scaled by 100
/// * The special value of 0 means limit is not set
///   * This is so that uninitialized storage implies no limit
///   * For an actual cap value of 0, use a zero mantissa and non-zero exponent
library AmountCapLib {
    function resolve(AmountCap self) internal pure returns (uint256) {
        uint256 amountCap = AmountCap.unwrap(self);

        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

    function toRawUint16(AmountCap self) internal pure returns (uint16) {
        return AmountCap.unwrap(self);
    }
}
