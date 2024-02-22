pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/stakedao/IStakeDao_ClaimRewards.sol)

interface IStakeDao_ClaimRewards {
  	struct LockStatus {
        bool[] locked;
        bool[] staked;
        bool lockSDT;
	  }
    function claimRewards(address[] calldata _gauges) external; 
    function claimAndLock(address[] memory _gauges, LockStatus memory _lockStatus) external;
}