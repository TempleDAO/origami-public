pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Operators} from "../../../common/access/Operators.sol";

contract DummyOperatorsUpgradeable is Initializable, Operators {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function addOperator(address _address) external override {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override {
        _removeOperator(_address);
    }
}
