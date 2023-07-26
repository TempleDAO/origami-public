pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGmxRewardDistributor.sol)

interface IGmxRewardDistributor {
    function tokensPerInterval() external view returns (uint256);
}
