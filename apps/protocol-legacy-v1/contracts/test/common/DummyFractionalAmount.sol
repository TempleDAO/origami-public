pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {FractionalAmount} from "../../common/FractionalAmount.sol";

contract DummyFractionalAmount {
    using FractionalAmount for FractionalAmount.Data;

    FractionalAmount.Data public fractionalRate;

    function set(uint128 _numerator, uint128 _denominator) external {
        fractionalRate.set(_numerator, _denominator);
    }

    function split(uint256 _inputAmount) external view returns (uint256 amount1, uint256 amount2) {
        return fractionalRate.split(_inputAmount);
    }

    function splitCalldata(FractionalAmount.Data calldata _fr, uint256 _inputAmount) external pure returns (uint256 amount1, uint256 amount2) {
        return _fr.split(_inputAmount);
    }

    function splitExplicit(uint256 _numerator, uint256 _denominator, uint256 _inputAmount) external pure returns (uint256 amount1, uint256 amount2) {
        return FractionalAmount.split(uint128(_numerator), uint128(_denominator), _inputAmount);
    }
}
