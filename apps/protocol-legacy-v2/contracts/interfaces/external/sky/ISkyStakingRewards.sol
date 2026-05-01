// SPDX-FileCopyrightText: © 2019-2021 Synthetix
// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: MIT AND AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// https://docs.synthetix.io/contracts/source/interfaces/istakingrewards
interface ISkyStakingRewards {
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Referral(uint16 indexed referral, address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event RewardsDistributionUpdated(address newRewardsDistribution);
    event Recovered(address token, uint256 amount);

    // Views

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function rewardsDistribution() external view returns (address);

    function rewardsToken() external view returns (IERC20);

    function stakingToken() external view returns (IERC20);

    function totalSupply() external view returns (uint256);

    function userRewardPerTokenPaid(address account) external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    function rewardPerTokenStored() external view returns (uint256);

    function lastUpdateTime() external view returns (uint256);

    function periodFinish() external view returns (uint256);

    function rewardsDuration() external view returns (uint256);

    // Mutative

    function exit() external;

    function getReward() external;

    function stake(uint256 amount) external;

    function stake(uint256 amount, uint16 referral) external;

    function withdraw(uint256 amount) external;

    function notifyRewardAmount(uint256 reward) external;

    function setRewardsDistribution(address _rewardsDistribution) external;

    function setRewardsDuration(uint256 _rewardsDuration) external;
}
