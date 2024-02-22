pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OrigamiElevatedAccessUpgradeable } from "contracts/common/access/OrigamiElevatedAccessUpgradeable.sol";
import { IOrigamiElevatedAccess } from "contracts/interfaces/common/access/IOrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";


/** @notice
 * - The first `DummyElevatedAccessUpgradeablev1` instance implements the OrigamiElevatedAccessUpgradeable as-is 
 * - The second `DummyElevatedAccessUpgradeablev2` instance implements OrigamiElevatedAccessUpgradeablev2
 *   where there are a couple of new storage vars (xxx and yyy) where the storage __gap needs to be updated.
 * 
 * Hardhat upgrades is used to verify that it's the correct representation
 */

/* solhint-disable func-name-mixedcase */
contract DummyElevatedAccessUpgradeablev1 is Initializable, OrigamiElevatedAccessUpgradeable, UUPSUpgradeable {

    uint256 v1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) initializer external {
        __OrigamiElevatedAccess_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    // A test so _authorizeUpgrade can be called
    function authorizeUpgrade() external {
        _authorizeUpgrade(address(this));
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyElevatedAccess
        override
    {}

    function do_init(address initialOwner) external {
        _init(initialOwner);
    }
    
    function checkOnlyElevatedAccess() external view onlyElevatedAccess returns (uint256) {
        return 1;
    }

    function OrigamiElevatedAccess_init(address initialOwner) external {
        __OrigamiElevatedAccess_init(initialOwner);
    }

    function OrigamiElevatedAccess_init_unchained(address initialOwner) external {
        __OrigamiElevatedAccess_init_unchained(initialOwner);
    }
}

/**
 * @notice Inherit to add Owner roles for DAO elevated access.
 */ 
abstract contract OrigamiElevatedAccessBasev2 is IOrigamiElevatedAccess {
    /**
     * @notice The address which is approved to execute normal operations on behalf of the DAO.
     */ 
    address public override owner;

    /**
     * @notice Explicit approval for an address to execute a function.
     * allowedCaller => function selector => true/false
     */
    mapping(address => mapping(bytes4 => bool)) public override explicitFunctionAccess;

    /// @dev Track proposed owner
    address private _proposedNewOwner;

    uint256 public xxx;

    function setXXX(uint256 _xxx) external onlyElevatedAccess {
        xxx = _xxx;
    }
    
    function _init(address initialOwner) internal {
        if (owner != address(0)) revert CommonEventsAndErrors.InvalidAccess();
        if (initialOwner == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        owner = initialOwner;
        xxx;
    }

    /**
     * @notice Proposes a new Executor.
     * Can only be called by the current executor or rescuer (if in resuce mode)
     */
    function proposeNewOwner(address account) external override onlyElevatedAccess {
        if (account == address(0)) revert CommonEventsAndErrors.InvalidAddress(account);
        emit NewOwnerProposed(owner, _proposedNewOwner, account);
        _proposedNewOwner = account;
    }

    /**
     * @notice Caller accepts the role as new Executor.
     * Can only be called by the proposed executor
     */
    function acceptOwner() external override {
        if (msg.sender != _proposedNewOwner) revert CommonEventsAndErrors.InvalidAccess();

        emit NewOwnerAccepted(owner, msg.sender);
        owner = msg.sender;
        delete _proposedNewOwner;
    }

    /**
     * @notice Grant `allowedCaller` the rights to call the function selectors in the access list.
     * @dev fnSelector == bytes4(keccak256("fn(argType1,argType2,...)"))
     */
    function setExplicitAccess(address allowedCaller, ExplicitAccess[] calldata access) external override onlyElevatedAccess {
        if (allowedCaller == address(0)) revert CommonEventsAndErrors.InvalidAddress(allowedCaller);
        uint256 _length = access.length;
        ExplicitAccess memory _access;
        for (uint256 i; i < _length; ++i) {
            _access = access[i];
            emit ExplicitAccessSet(allowedCaller, _access.fnSelector, _access.allowed);
            explicitFunctionAccess[allowedCaller][_access.fnSelector] = _access.allowed;
        }
    }

    function isElevatedAccess(address caller, bytes4 fnSelector) internal view returns (bool) {
        if (caller == owner) {
            return true;
        }
        return explicitFunctionAccess[caller][fnSelector];
    }

    /**
     * @notice The owner is allowed to call, or if explicit access has been given to the caller.
     * @dev Important: Only for use when called from an *external* contract. 
     * If a function with this modifier is called internally then the `msg.sig` 
     * will still refer to the top level externally called function.
     */
    modifier onlyElevatedAccess() {
        if (!isElevatedAccess(msg.sender, msg.sig)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}

/**
 * @notice Inherit to add Owner roles for DAO elevated access.
 */ 
abstract contract OrigamiElevatedAccessUpgradeablev2 is Initializable, OrigamiElevatedAccessBasev2 {
    uint256 public yyy;

    function __OrigamiElevatedAccess_init(address initialOwner) internal onlyInitializing {
        __OrigamiElevatedAccess_init_unchained(initialOwner);
    }

    function __OrigamiElevatedAccess_init_unchained(address initialOwner) internal onlyInitializing {
        _init(initialOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}


/* solhint-disable func-name-mixedcase */
contract DummyElevatedAccessUpgradeablev2 is Initializable, OrigamiElevatedAccessUpgradeablev2, UUPSUpgradeable {

    // bytes32 v2;
    uint256 v1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) initializer external {
        __OrigamiElevatedAccess_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    // A test so _authorizeUpgrade can be called
    function authorizeUpgrade() external {
        _authorizeUpgrade(address(this));
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyElevatedAccess
        override
    {}

    function do_init(address initialOwner) external {
        _init(initialOwner);
    }
    
    function checkOnlyElevatedAccess() external view onlyElevatedAccess returns (uint256) {
        return 1;
    }

    function OrigamiElevatedAccess_init(address initialOwner) external {
        __OrigamiElevatedAccess_init(initialOwner);
    }

    function OrigamiElevatedAccess_init_unchained(address initialOwner) external {
        __OrigamiElevatedAccess_init_unchained(initialOwner);
    }
}
