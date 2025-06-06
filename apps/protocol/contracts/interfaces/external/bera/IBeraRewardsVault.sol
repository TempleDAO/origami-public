pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/bera/IBerachainRewardsVault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Synthetix style
// https://docs.berachain.com/developers/contracts/rewards-vault
interface IBeraRewardsVault {
    // MUTATIVE

    /// @notice Allows msg.sender to set another address to claim and manage their rewards.
    /// @param _operator The address that will be allowed to claim and manage rewards.
    function setOperator(address _operator) external;

    /// @notice Stake tokens in the vault.
    /// @param amount The amount of tokens to stake.
    function stake(uint256 amount) external;

    /// @notice Withdraw the staked tokens from the vault.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint256 amount) external;

    /// @notice Stake tokens on behalf of another account.
    /// @param account The account to stake for.
    /// @param amount The amount of tokens to stake.
    function delegateStake(address account, uint256 amount) external;

    /// @notice Withdraw tokens staked on behalf of another account by the delegate (msg.sender).
    /// @param account The account to withdraw for.
    /// @param amount The amount of tokens to withdraw.
    function delegateWithdraw(address account, uint256 amount) external;

    /// @notice Exit the vault with the staked tokens and claim the reward.
    /// @dev Only the account holder can call this function, not the operator.
    /// @dev Clears out the user self-staked balance and rewards.
    /// @param recipient The address to send the 'BGT' reward to.
    function exit(address recipient) external;

    /// @notice Claim the reward.
    /// @dev The operator only handles BGT, not STAKING_TOKEN.
    /// @dev Callable by the operator or the account holder.
    /// @param account The account to get the reward for.
    /// @param recipient The address to send the reward to.
    /// @return The amount of the reward claimed.
    function getReward(address account, address recipient) external returns (uint256);
    
    /// @notice Add an incentive token to the vault.
    /// @notice The incentive token's transfer should not exceed a gas usage of 500k units.
    /// In case the transfer exceeds 500k gas units, your incentive will fail to be transferred to the validator and
    /// its delegates.
    /// @param token The address of the token to add as an incentive.
    /// @param amount The amount of the token to add as an incentive.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    /// @dev Permissioned function, only callable by incentive token manager.
    function addIncentive(address token, uint256 amount, uint256 incentiveRate) external;

    // VIEWS

    /// @dev The maximum count of incentive tokens that can be stored.
    function maxIncentiveTokensCount() external view returns (uint8);

    /// @dev the mapping of incentive token to its incentive data.
    function incentives(address token) external view returns (
        uint256 minIncentiveRate, 
        uint256 incentiveRate, 
        uint256 amountRemaining, 
        address manager
    );

    /// @dev The list of whitelisted tokens.
    function whitelistedTokens(uint256 index) external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    function userRewardPerTokenPaid(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function distributor() external view returns (address);

    /// @notice Get the amount staked by a delegate on behalf of an account.
    /// @return The amount staked by a delegate.
    function getDelegateStake(address account, address delegate) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    /// @notice Get the total amount staked by delegates.
    /// @return The total amount staked by delegates.
    function getTotalDelegateStaked(address account) external view returns (uint256);

    /// @notice Get the list of whitelisted tokens.
    /// @return The list of whitelisted tokens.
    function getWhitelistedTokens() external view returns (address[] memory);

    /// @notice Get the count of active incentive tokens.
    /// @return The count of active incentive tokens.
    function getWhitelistedTokensCount() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);
    
    /// @notice Get the operator for an account.
    /// @param account The account to get the operator for.
    /// @return The operator for the account.
    function operator(address account) external view returns (address);

    /// @dev Gives current reward per token, result is scaled by PRECISION.
    function rewardPerToken() external view returns (uint256);

    /// @notice The total supply of the staked tokens.
    function totalSupply() external view returns (uint256);
 
    /// @notice ERC20 token which users stake to earn rewards.
    function stakeToken() external view returns (IERC20);

    /// @notice ERC20 token in which rewards are denominated and distributed.
    function rewardToken() external view returns (IERC20);

    /// @notice The reward rate for the current reward period scaled by PRECISION.
    function rewardRate() external view returns (uint256);

    /// @notice The amount of undistributed rewards scaled by PRECISION.
    function undistributedRewards() external view returns (uint256);

    /// @notice The last updated reward per token scaled by PRECISION.
    function rewardPerTokenStored() external view returns (uint256);

    /// @notice The end of the current reward period, where we need to start a new one.
    function periodFinish() external view returns (uint256);

    /// @notice The time over which the rewards will be distributed. Current default is 7 days.
    function rewardsDuration() external view returns (uint256);

    /// @notice The last time the rewards were updated.
    function lastUpdateTime() external view returns (uint256);

}
