pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (common/access/Operators.sol)

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @notice Inherit to add an Operator role which multiple addreses can be granted.
/// @dev Derived classes to implement addOperator() and removeOperator()
abstract contract Operators is Initializable {
    /// @notice A set of addresses which are approved to run operations.
    mapping(address => bool) public operators;

    event AddedOperator(address indexed account);
    event RemovedOperator(address indexed account);

    error OnlyOperators(address caller);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Operators_init() internal onlyInitializing {
        __Operators_init_unchained();
    }

    function __Operators_init_unchained() internal onlyInitializing {
    }

    function _addOperator(address _account) internal {
        emit AddedOperator(_account);
        operators[_account] = true;
    }

    /// @notice Grant `_account` the operator role
    /// @dev Derived classes to implement and add protection on who can call
    function addOperator(address _account) external virtual;

    function _removeOperator(address _account) internal {
        emit RemovedOperator(_account);
        delete operators[_account];
    }

    /// @notice Revoke the operator role from `_account`
    /// @dev Derived classes to implement and add protection on who can call
    function removeOperator(address _account) external virtual;

    modifier onlyOperators() {
        if (!operators[msg.sender]) revert OnlyOperators(msg.sender);
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
