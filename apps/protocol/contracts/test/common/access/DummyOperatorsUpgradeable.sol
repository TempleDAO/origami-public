pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OperatorsUpgradeable} from "../../../common/access/OperatorsUpgradeable.sol";

contract DummyOperatorsUpgradeable is Initializable, OperatorsUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Operators_init();
    }

    function addOperator(address _address) external override {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override {
        _removeOperator(_address);
    }

    // To test onlyInitializing modifier
    function operators_init() external {
        __Operators_init();
    }

    // To test onlyInitializing modifier
    function operators_init_unchained() external {
        __Operators_init_unchained();
    }
}
