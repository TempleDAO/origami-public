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
     * @notice Verify the new amount requested for the sender does not breach the
     * cap in this rolling period.
     */
    function preCheck(address onBehalfOf, uint256 amount) external;
}
