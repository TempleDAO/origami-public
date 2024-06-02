pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol)

/**
 * @title Origami Circuit Breaker
 * 
 * @dev Forked from https://github.com/TempleDAO/temple/tree/76da0e528f441d7999bb42092727aaad193506df/protocol/contracts/interfaces/v2/circuitBreaker
 * 
 * @notice A circuit breaker can perform checks and record state for transactions which have
 * already happened cumulative totals, totals within a rolling period window,
 * sender specific totals, etc.
 */
interface IOrigamiCircuitBreaker {

    /**
     * @notice Verify the new amount requested does not breach the
     * limits.
     */
    function preCheck(uint256 amount) external;

    /**
     * @notice The maximum allowed amount to be transacted
     */
    function cap() external view returns (uint256);

    /**
     * @notice The total utilised out of the cap so far
     */
    function currentUtilisation() external view returns (uint256 amount);

    /**
     * @notice The unutilised amount
     */
    function available() external view returns (uint256);
}
