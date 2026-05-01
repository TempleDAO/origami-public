pragma solidity ^0.8.19;

// SPDX-License-Identifier: AGPL-3.0-or-later

/// @dev Read immutable args from a Solady LibClone deployment.
/// This immutable data is stored in the runtime code of the cloned implementation
// The Solady clone immutable args start at byte 45 (0x2d) of the RUNTIME
// https://github.com/Vectorized/solady/blob/271807270b1e14e541a231ff76a869accca7546d/src/utils/LibClone.sol#L445
library ClonesImmutableReader {
    /// @dev The solady defined start of immutable args in the contract runtime code.
    /// Callers are trusted to use sensible `argOffset` for that arg type such that it
    /// doesn't go past the codesize for the clone instance.
    uint256 private constant _IMMUTABLE_ARGS_START = 0x2d;

    /// @dev Expects packed 20 bytes starting at argOffset
    function _getArgAddress(uint256 argOffset) internal view returns (address result) {
        assembly ("memory-safe") {
            // Copy one 32 byte word from runtime code into scratch[0..31]
            extcodecopy(address(), 0x00, add(_IMMUTABLE_ARGS_START, argOffset), 0x20)

            // shift right 12 bytes into an address (which is 20 bytes) and assign to the result
            result := shr(0x60, mload(0x00))
        }
    }

    /// @dev Expects 1x 32 byte word starting at argOffset
    function _getArgBytes32(uint256 argOffset) internal view returns (bytes32 result) {
        assembly ("memory-safe") {
            // Copy one 32 byte word from runtime code into scratch[0..31]
            extcodecopy(address(), 0x00, add(_IMMUTABLE_ARGS_START, argOffset), 0x20)

            result := mload(0x00)
        }
    }

    /// @dev Expects 1x 32 byte word starting at argOffset
    function _getArgUint256(uint256 argOffset) internal view returns (uint256 result) {
        return uint256(_getArgBytes32(argOffset));
    }

    /// @dev Expects packed 1 byte starting at argOffset
    function _getArgUint8(uint256 argOffset) internal view returns (uint8 result) {
        assembly ("memory-safe") {
            // Copy exactly 1 byte from runtime code into scratch[0..0]
            extcodecopy(address(), 0x00, add(_IMMUTABLE_ARGS_START, argOffset), 0x01)

            // Take the most-significant byte of the word at m[0] (the one we just wrote).
            // 'byte(i, x)' indexes from MSB=0..LSB=31.
            result := byte(0, mload(0x00))
        }
    }
}
