pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol)

import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";

/**
 * @title Origami Circuit Breaker Proxy
 * 
 * @dev Forked from https://github.com/TempleDAO/temple/tree/76da0e528f441d7999bb42092727aaad193506df/protocol/contracts/interfaces/v2/circuitBreaker
 *
 * @notice Direct circuit breaker requests to the correct underlying implementation,
 * based on a pre-defined bytes32 identifier, and a token.
 */
interface IOrigamiCircuitBreakerProxy {
    event CircuitBreakerSet(bytes32 indexed identifier, address indexed token, address circuitBreaker);
    event IdentifierForCallerSet(address indexed caller, string identifierString, bytes32 identifier);

    /**
     * @notice A calling contract of the circuit breaker (eg lovToken or exit vault) is mapped to an identifier
     * which means circuit breaker caps can be shared across multiple callers.
     */
    function callerToIdentifier(address callingContract) external view returns (bytes32 identifier);

    /**
     * @notice The mapping of a (identifier, tokenAddress) tuple to the underlying circuit breaker contract
     */
    function circuitBreakers(
        bytes32 identifier, 
        address token
    ) external view returns (IOrigamiCircuitBreaker implementation);

    /**
     * @notice Set the identifier for a given caller of the circuit breaker. These identifiers
     * can be shared, such that multiple contracts share the same cap limits for a given token.
     */
    function setIdentifierForCaller(
        address caller, 
        string memory identifierString
    ) external;

    /**
     * @notice Set the address of the circuit breaker for a particular identifier and token
     */
    function setCircuitBreaker(
        bytes32 identifier,
        address token,
        address circuitBreaker
    ) external;

    /**
     * @notice For a given identifier & token, verify the new amount requested for the sender does not breach the
     * limits.
     */
    function preCheck(
        address token,
        uint256 amount
    ) external;

    /**
     * @notice The maximum allowed amount to be transacted
     */
    function cap(
        address token,
        address caller
    ) external view returns (uint256);

    /**
     * @notice The total utilised out of the cap so far
     */
    function currentUtilisation(
        address token,
        address caller
    ) external view returns (uint256);

    /**
     * @notice The unutilised amount
     */
    function available(
        address token,
        address caller
    ) external view returns (uint256);

    /**
     * @notice The set of all identifiers registered
     */
    function identifiers() external view returns (bytes32[] memory);
}
