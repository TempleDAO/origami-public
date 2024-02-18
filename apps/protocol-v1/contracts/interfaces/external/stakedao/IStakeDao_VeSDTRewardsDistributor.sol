pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_VeSDTRewardsDistributor.sol)

interface IStakeDao_VeSDTRewardsDistributor {
    function claim(address user) external returns (uint256); // Default for msg.sender
    function last_token_time() external view returns (uint256);
    function ve_supply(uint week) external view returns (uint256);
    function tokens_per_week(uint week) external view returns (uint256);
    function start_time() external view returns (uint256);
    function time_cursor_of(address user) external view returns (uint256);
    function token() external view returns (address);
    function token_last_balance() external view returns (uint256);
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
    function user_epoch_of(address) external view returns (uint256);
    function time_cursor() external view returns (uint256);
}