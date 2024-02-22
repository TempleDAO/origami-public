pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/circuitBreaker/OrigamiCircuitBreakerProxy.sol)

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiCircuitBreaker } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreaker.sol";
import { IOrigamiCircuitBreakerProxy } from "contracts/interfaces/common/circuitBreaker/IOrigamiCircuitBreakerProxy.sol";

/**
 * @title Origami Circuit Breaker Proxy
 * 
 * @dev Forked from https://github.com/TempleDAO/temple/tree/76da0e528f441d7999bb42092727aaad193506df/protocol/contracts/v2/circuitBreaker
 *
 * @notice Direct circuit breaker requests to the correct underlying implementation,
 * based on a pre-defined bytes32 identifier, and a token.
 */
contract OrigamiCircuitBreakerProxy is IOrigamiCircuitBreakerProxy, OrigamiElevatedAccess {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice A calling contract of the circuit breaker (eg lovToken or exit vault) is mapped to an identifier
     * which means circuit breaker caps can be shared across multiple callers.
     */
    mapping(address callingContract => bytes32 identifier) public override callerToIdentifier;

    /**
     * @notice The mapping of a (identifier, tokenAddress) tuple to the underlying circuit breaker contract
     */
    mapping(bytes32 identifier => mapping(address token => IOrigamiCircuitBreaker implementation)) public override circuitBreakers;

    /**
     * @notice The list of all identifiers utilised
     */
    EnumerableSet.Bytes32Set internal _identifiers;

    constructor(
        address _initialOwner
    ) OrigamiElevatedAccess(_initialOwner)
    // solhint-disable-next-line no-empty-blocks
    {}

    /**
     * @notice Set the identifier for a given caller of the circuit breaker. These identifiers
     * can be shared, such that multiple contracts share the same cap limits for a given token.
     */
    function setIdentifierForCaller(
        address caller, 
        string calldata identifierString
    ) external override onlyElevatedAccess {
        if (caller == address(0)) revert CommonEventsAndErrors.InvalidAddress(caller);
        if (bytes(identifierString).length == 0) revert CommonEventsAndErrors.InvalidParam();

        bytes32 _identifier = keccak256(bytes(identifierString));
        callerToIdentifier[caller] = _identifier;
        _identifiers.add(_identifier);

        emit IdentifierForCallerSet(caller, identifierString, _identifier);
    }

    /**
     * @notice Set the address of the circuit breaker for a particular identifier and token
     * @dev address(0) is allowed as a special case for native ETH
     */
    function setCircuitBreaker(
        bytes32 identifier,
        address token,
        address circuitBreaker
    ) external override onlyElevatedAccess {
        if (!_identifiers.contains(identifier)) revert CommonEventsAndErrors.InvalidParam();
        if (circuitBreaker == address(0)) revert CommonEventsAndErrors.InvalidAddress(circuitBreaker);

        circuitBreakers[identifier][token] = IOrigamiCircuitBreaker(circuitBreaker);
        emit CircuitBreakerSet(identifier, token, circuitBreaker);
    }

    /**
     * @notice For a given identifier & token, verify the new amount requested for the sender does not breach the
     * cap in this rolling period.
     */
    function preCheck(
        address token,
        address onBehalfOf,
        uint256 amount
    ) external override {
        bytes32 _identifier = callerToIdentifier[msg.sender];

        // This will fail with an EVM error if not in the mapping, which is fine.
        // Not worth a specific custom error check prior.
        circuitBreakers[_identifier][token].preCheck(onBehalfOf, amount);
    }

    /**
     * @notice The set of all identifiers registered
     */
    function identifiers() external override view returns (bytes32[] memory) {
        return _identifiers.values();
    }
}