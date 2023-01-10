pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {FractionalAmount} from "../../common/FractionalAmount.sol";

contract DummyFractionalAmount {
    using FractionalAmount for FractionalAmount.Data;

    FractionalAmount.Data public fractionalRate;

    function set(uint128 _numerator, uint128 _denominator) external {
        fractionalRate.set(_numerator, _denominator);
    }

    function split(uint256 _inputAmount) external view returns (uint256 numeratorAmount, uint256 denominatorAmount) {
        return fractionalRate.split(_inputAmount);
    }
}
