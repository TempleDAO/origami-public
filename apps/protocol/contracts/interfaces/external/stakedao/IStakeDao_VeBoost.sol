pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_VeBoost.sol)

interface IStakeDao_VeBoost {
    event Boost(address indexed _from, address indexed _to, uint256 _bias, uint256 _slope, uint256 _start);
    
    function boost(address _to, uint256 _amount, uint256 _endtime, address _from) external;
    function balanceOf(address _user) external view returns (uint256);
}
