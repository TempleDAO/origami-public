pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_LiquidityGaugeV4.sol)

interface IStakeDao_LiquidityGaugeV4 {
    function reward_count() external view returns (uint256);
    function reward_tokens(uint256 index) external view returns (address);
}
