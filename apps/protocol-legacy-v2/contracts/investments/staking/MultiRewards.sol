pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/investments/staking/MultiRewards.sol)

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title MultiRewards
 * @dev Fork of https://berascan.com/address/0x75f3be06b02e235f6d0e7ef2d462b29739168301#code
 * Also keeps track of totalUnclaimedRewards
 * Assumes reward tokens are not anything weird like fee-on-transfer
 */
abstract contract MultiRewards is ReentrancyGuard, IMultiRewards {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The token that users stake to earn rewards
     * @dev This is the base token that users deposit into the contract
     */
    IERC20 private immutable _stakingToken;

    /**
     * @notice Stores reward-related data for each reward token
     * @dev Maps reward token addresses to their Reward struct containing distribution parameters
     */
    mapping(address => Reward) public override rewardData;

    /**
     * @notice Array of all reward token addresses
     * @dev Used to iterate through all reward tokens when updating or claiming rewards
     */
    address[] public override rewardTokens;

    /**
     * @notice Tracks the reward per token paid to each user for each reward token
     * @dev Maps user address to reward token address to amount already paid
     * Used to calculate new rewards since last claim
     */
    mapping(address user => mapping(address rewardToken => uint256 alreadyPaidAmount)) public override userRewardPerTokenPaid;

    /**
     * @notice Tracks the unclaimed rewards for each user for each reward token
     * @dev Maps user address to reward token address to unclaimed amount
     */
    mapping(address user => mapping(address rewardToken => uint256 unclaimedAmount)) public override rewards;

    /**
     * @notice Tracks the unclaimed rewards across all users for each reward token
     */
    mapping(address rewardToken => uint256 amount) public override totalUnclaimedRewards;

    /**
     * @notice The total amount of staking tokens in the contract
     * @dev Used to calculate rewards per token
     */
    uint256 internal _totalSupply;

    /**
     * @notice Maps user addresses to their staked token balance
     * @dev Internal mapping used to track individual stake amounts
     */
    mapping(address => uint256) internal _balances;

    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the reward for the given account before executing the
     * function body.
     * @param account address The account to update the reward for.
     */
    modifier updateReward(address account) {
        for (uint256 i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];

            uint256 latestRewardPerToken = rewardPerToken(token);
            Reward storage $ = rewardData[token];
            $.rewardPerTokenStored = latestRewardPerToken;
            $.lastUpdateTime = lastTimeRewardApplicable(token);

            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = latestRewardPerToken;
            }
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs the MultiRewards contract.
     * @param stakingToken_ address The token that users stake to earn rewards.
     */
    constructor(address stakingToken_) {
        _stakingToken = IERC20(stakingToken_);
    }

    /*//////////////////////////////////////////////////////////////
                               READS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMultiRewards
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IMultiRewards
    function balanceOf(address account)
        external
        override 
        view
        returns (uint256 _balance)
    {
        return _balances[account];
    }

    /// @inheritdoc IMultiRewards
    function lastTimeRewardApplicable(address _rewardsToken)
        public
        override 
        view
        returns (uint256)
    {
        // min value between timestamp and period finish
        uint256 periodFinish = rewardData[_rewardsToken].periodFinish;
        uint256 ts = block.timestamp;
        return ts < periodFinish ? ts : periodFinish;
    }

    /// @inheritdoc IMultiRewards
    function rewardPerToken(address _rewardsToken)
        public
        override 
        view
        returns (uint256)
    {
        Reward storage $ = rewardData[_rewardsToken];
        if (_totalSupply == 0) {
            return $.rewardPerTokenStored;
        }
        return $.rewardPerTokenStored
            + (
                lastTimeRewardApplicable(_rewardsToken) - $.lastUpdateTime
            ) * $.rewardRate * 1e18 / _totalSupply;
    }

    /// @inheritdoc IMultiRewards
    function earned(address account, address _rewardsToken)
        public
        override 
        view
        returns (uint256)
    {
        return (
            _balances[account]
                * (
                    rewardPerToken(_rewardsToken)
                        - userRewardPerTokenPaid[account][_rewardsToken]
                )
        ) / 1e18 + rewards[account][_rewardsToken];
    }

    /// @inheritdoc IMultiRewards
    function getRewardForDuration(address _rewardsToken)
        external
        override 
        view
        returns (uint256)
    {
        Reward storage $ = rewardData[_rewardsToken];
        return $.rewardRate * $.rewardsDuration;
    }

    function stakingToken() public override view returns (address) {
        return address(_stakingToken);
    }

    /*//////////////////////////////////////////////////////////////
                            WRITES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMultiRewards
    function stake(uint256 amount)
        external
        override 
        nonReentrant
        updateReward(msg.sender)
    {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;

        // transfer staking token in then hook stake, for hook to have access to collateral
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        onStake(amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Hook called in the stake function after transfering staking token in
     * @param amount The amount of staking token transferred in to the contract
     */
    function onStake(uint256 amount) internal virtual;

    /// @inheritdoc IMultiRewards
    function withdraw(uint256 amount)
        public
        override 
        nonReentrant
        updateReward(msg.sender)
    {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        uint256 balance = _balances[msg.sender];
        if (amount > balance) revert CommonEventsAndErrors.InvalidAmount(address(_stakingToken), amount);
        
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = balance - amount;

        // hook withdraw then transfer staking token out
        onWithdraw(amount);
        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Hook called in withdraw function before transferring staking token out
     * @param amount The amount of staking token to be transferred out of the contract
     */
    function onWithdraw(uint256 amount) internal virtual;

    /// @inheritdoc IMultiRewards
    function getRewardForUser(address _user)
        public
        override 
        nonReentrant
        updateReward(_user)
    {
        onReward();
        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[_user][_rewardsToken];
            if (reward > 0) {
                // Skip any reward tokens which fail on transfer,
                // so the rest can be claimed still
                // Limit the gas to 200k to avoid potential gas DoS for dodgy reward tokens
                // (which requires the low level call)
                // This also adds SafeERC20 checks.
                (bool success, bytes memory data) = _rewardsToken.call{gas: 200_000}(
                    abi.encodeWithSelector(IERC20.transfer.selector, _user, reward)
                );
                if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                    rewards[_user][_rewardsToken] = 0;
                    totalUnclaimedRewards[_rewardsToken] -= reward;
                    emit RewardPaid(_user, _rewardsToken, reward);
                } else {
                    continue;
                }
            }
        }
    }

    /**
     * @notice Hook called in getRewardForUser function
     */
    function onReward() internal virtual;

    /// @inheritdoc IMultiRewards
    function getReward() public override {
        getRewardForUser(msg.sender);
    }

    /// @inheritdoc IMultiRewards
    function exit() external override {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /*//////////////////////////////////////////////////////////////
                            RESTRICTED
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a reward token to the contract.
     * @param _rewardsToken       address The address of the reward token.
     * @param _rewardsDuration    uint256 The duration of the rewards period.
     */
    function _addReward(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) internal {
        if (_rewardsDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        
        rewardTokens.push(_rewardsToken);
        // rewardsDistributor is left uninitialized as it's unused.
        rewardData[_rewardsToken].rewardsDuration = _rewardsDuration;
        emit RewardStored(_rewardsToken, _rewardsDuration);
    }

    /**
     * @notice Removes a reward token from the contract.
     * @param _rewardsToken address The address of the reward token.
     */
    function _removeReward(address _rewardsToken) internal returns (uint256 oldRewardTokenIndex) {
        if (rewardData[_rewardsToken].rewardsDuration == 0) revert RewardDoesntExist();
        if (block.timestamp < rewardData[_rewardsToken].periodFinish) revert PeriodNotFinished();

        // Remove from the array
        for (oldRewardTokenIndex = 0; oldRewardTokenIndex < rewardTokens.length; oldRewardTokenIndex++) {
            if (rewardTokens[oldRewardTokenIndex] == _rewardsToken) {
                rewardTokens[oldRewardTokenIndex] = rewardTokens[rewardTokens.length - 1];
                rewardTokens.pop();
                break;
            }
        }

        delete rewardData[_rewardsToken];
        emit RewardRemoved(_rewardsToken);
    }

    /**
     * @notice Notifies the contract that reward tokens have been sent to the contract.
     * @notice Any tokens for notification must already be pulled into the contract
     * @param _rewardsToken address The address of the reward token.
     * @param reward        uint256 The amount of reward tokens.
     */
    function _notifyRewardAmount(address _rewardsToken, uint256 reward)
        internal
        updateReward(address(0))
    {
        Reward storage $ = rewardData[_rewardsToken];
        totalUnclaimedRewards[_rewardsToken] += reward;

        // add in the prior residual amount and account for new residual
        // @dev residual used to account for precision loss when dividing reward by rewardsDuration
        reward = reward + $.rewardResidual;
        uint256 _rewardsDuration = $.rewardsDuration;
        uint256 _rewardResidual = $.rewardResidual = reward % _rewardsDuration;
        reward = reward - _rewardResidual;

        if (block.timestamp >= $.periodFinish) {
            $.rewardRate = reward / _rewardsDuration;
        } else {
            uint256 remaining = $.periodFinish - block.timestamp;
            uint256 leftover = remaining * $.rewardRate;

            // Calculate total and its residual
            uint256 totalAmount = reward + leftover + _rewardResidual;
            $.rewardResidual = _rewardResidual = totalAmount % _rewardsDuration;

            // Remove residual before setting rate
            totalAmount = totalAmount - _rewardResidual;
            $.rewardRate = totalAmount / _rewardsDuration;
        }

        $.lastUpdateTime = block.timestamp;
        $.periodFinish = block.timestamp + _rewardsDuration;
        emit RewardAdded(_rewardsToken, reward);
    }

    /**
     * @notice Recovers ERC20 tokens sent to the contract.
     * @dev Added to support recovering rewards from other systems which aren't to be distributed
     * directly to users.
     * If a reward token was removed and then recovered, then prior to adding it again
     * that balance must be depoisted back into the contract again.
     */
    function _recoverERC20(
        address to,
        address tokenAddress,
        uint256 tokenAmount
    ) internal {
        if (rewardData[tokenAddress].lastUpdateTime != 0) revert CannotRecoverRewardToken();
        IERC20(tokenAddress).safeTransfer(to, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Updates the reward duration for a reward token.
     * @param _rewardsToken    address The address of the reward token.
     * @param _rewardsDuration uint256 The new duration of the rewards period.
     */
    function _setRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) internal {
        if (_rewardsDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        Reward storage $ = rewardData[_rewardsToken];
        if ($.rewardsDuration == 0) revert RewardDoesntExist();

        if (block.timestamp < $.periodFinish) {
            uint256 remaining = $.periodFinish - block.timestamp;
            uint256 leftover = remaining * $.rewardRate;

            // Calculate total and its residual
            uint256 totalAmount = leftover + $.rewardResidual;
            $.rewardResidual = totalAmount % _rewardsDuration;

            // Remove residual before setting rate
            totalAmount = totalAmount - $.rewardResidual;
            $.rewardRate = totalAmount / _rewardsDuration;
        }

        $.lastUpdateTime = block.timestamp;
        $.periodFinish = block.timestamp + _rewardsDuration;

        $.rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsToken, _rewardsDuration);
    }
}
