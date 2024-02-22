pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (libraries/CommonEventsAndErrors.sol)

/// @notice A collection of common events and errors thrown within the Origami contracts
library CommonEventsAndErrors {
    error InsufficientBalance(address token, uint256 required, uint256 balance);
    error InvalidToken(address token);
    error InvalidParam();
    error InvalidAddress(address addr);
    error InvalidAmount(address token, uint256 amount);
    error ExpectedNonZero();
    error Slippage(uint256 minAmountExpected, uint256 actualAmount);
    error IsPaused();
    error UnknownExecuteError(bytes returndata);
    error InvalidAccess();

    event TokenRecovered(address indexed to, address indexed token, uint256 amount);
}
