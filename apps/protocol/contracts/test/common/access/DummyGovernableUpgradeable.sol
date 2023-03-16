pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GovernableUpgradeable} from "../../../common/access/GovernableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DummyGovernableUpgradeable is Initializable, GovernableUpgradeable, UUPSUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialGovernor) initializer external {
        __Governable_init(initialGovernor);
        __UUPSUpgradeable_init();
    }

    // A test so _authorizeUpgrade can be called
    function authorizeUpgrade() external {
        _authorizeUpgrade(address(this));
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyGov
        override
    {}
    
    function do_init(address initialGovernor) external {
        _init(initialGovernor);
    }
    
    function checkOnlyGov() external view onlyGov returns (uint256) {
        return 1;
    }

    function Governable_init(address initialGovernor) external {
        __Governable_init(initialGovernor);
    }

    function Governable_init_unchained(address initialGovernor) external {
        __Governable_init_unchained(initialGovernor);
    }
}
