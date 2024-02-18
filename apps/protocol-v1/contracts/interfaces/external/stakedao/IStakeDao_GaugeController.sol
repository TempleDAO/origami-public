pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_GaugeController.sol)

interface IStakeDao_GaugeController {
    event VoteForGauge(uint256 time, address user, address gauge_addr, uint256 weight);
    function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external;
    function vote_user_power(address user) external view returns (uint256);
}