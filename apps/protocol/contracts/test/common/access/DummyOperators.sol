pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Operators} from "../../../common/access/Operators.sol";

contract DummyOperators is Operators {
    uint256 public foo;

    function addOperator(address _address) external override {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override {
        _removeOperator(_address);
    }

    function setFoo(uint256 _foo) external onlyOperators {
        foo = _foo;
    }

}
