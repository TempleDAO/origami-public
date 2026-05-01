// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

// FlagsLib.sol taken from the following commit:
// https://github.com/euler-xyz/euler-vault-kit/commit/3d9120ecd8f8725f370c8a13598e0e09a454d5f7

// The following declaration was not part of this original file,
// instead it was imported from another file with `import {Flags} from "./Types.sol";`
// For simplicity, it was included in this snippet.
type Flags is uint32;

/// @title FlagsLib
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Library for `Flags` custom type
library FlagsLib {
    /// @dev Are *all* of the flags in bitMask set?
    function isSet(Flags self, uint32 bitMask) internal pure returns (bool) {
        return (Flags.unwrap(self) & bitMask) == bitMask;
    }

    /// @dev Are *none* of the flags in bitMask set?
    function isNotSet(Flags self, uint32 bitMask) internal pure returns (bool) {
        return (Flags.unwrap(self) & bitMask) == 0;
    }

    function toUint32(Flags self) internal pure returns (uint32) {
        return Flags.unwrap(self);
    }
}
