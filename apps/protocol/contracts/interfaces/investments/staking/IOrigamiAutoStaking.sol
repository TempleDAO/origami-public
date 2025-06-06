pragma solidity ^0.8.0;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol)

import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

/**
 * @title Origami Auto-Staking
 * @notice This is inspired by the infrared rewards vault contract at https://berascan.com/address/0x75f3be06b02e235f6d0e7ef2d462b29739168301#code
 *   - This contract deposits tokens into an underlying rewards vault, harvests the rewards and post-processes those rewards in order to pay out
 *     different tokens than what was claimed from the underlying vault. 
 *     For example within Infrared vaults, this can claim iBGT from the reward vaults, deposit into oriBGT and then 
 *     distribute oriBGT to users to claim
 *   - Stakers can withdraw their original tokens staked in full.
 * 
 * The vault can operate in two modes:
 *   - Single-Reward mode: Tokens other than the 'primary' reward token are sent to a swapper, which will sell those into more of the 'primary'
 *     reward token. Users will only be distributed the 'primary' reward token.
 *   - Multi-Reward mode: Tokens other than the 'primary' reward token are distributed directly to the users. The underlying reward tokens claimed
 *     may still be processed after claiming (eg iBGT => oriBGT)
 * 
 * @dev This contract uses the MultiRewards contract to distribute rewards to vault stakers, this is taken from curve.fi. (inspired by Synthetix).
 * Does not support staking tokens with non-standard ERC20 transfer tax behavior.
 */
 interface IOrigamiAutoStaking is IMultiRewards, IOrigamiSwapCallback {
    struct TokenAndAmount {
        address token;
        uint256 amount;
    }

    struct Paused {
        bool onStake;
        bool onWithdraw;
        bool onGetReward;
    }

    error MaxNumberOfRewards();
    error InSingleRewardMode();
    error InMultiRewardMode();

    event PerformanceFeesSet(address indexed rewardsToken, uint256 feeBps);
    event PerformanceFeesCollected(uint256 feeAmount);
    event FeeCollectorSet(address indexed feeCollector);
    event SwapperSet(address indexed newSwapper);
    event RestrictedPublicHarvestSet(bool value);
    event PostProcessingDisabledSet(bool value);
    event PausedSet(bool onStake, bool onWithdraw, bool onGetReward);

    /// @notice public function to harvest rewards from the underlying vault
    function harvestVault() external;

    /**
     * @notice Updates reward duration for a specific reward token
     * @param _rewardsToken The address of the reward token
     * @param _rewardsDuration The new duration in seconds
     */
    function updateRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external;

    /**
     * @notice Adds a new reward token to the vault
     * @dev Cannot exceed maximum number of reward tokens
     * @param _rewardsToken The reward token to add
     * @param _rewardsDuration The reward period duration
     * @param _performanceFeeBps The performance fee in basis points taken on this rewward token
     */
    function addReward(
        address _rewardsToken,
        uint256 _rewardsDuration,
        uint256 _performanceFeeBps
    ) external;

    /**
     * @notice Used to remove malicious or unused reward tokens
     */
    function removeReward(address _rewardsToken) external;

    /// @notice Set the swapper contract responsible for swapping reward tokens to the base asset.
    function setSwapper(address _swapper) external;

    /// @notice Set whether harvestVault() is restricted to elevated access only
    function setRestrictedPublicHarvest(bool value) external;

    /**
     * @notice Notifies the vault of newly added rewards
     * @dev Updates internal reward rate calculations
     * @param _rewardToken The reward token address
     * @param _reward The amount of new rewards
     */
    function notifyRewardAmount(address _rewardToken, uint256 _reward)
        external;

    /**
     * @notice Recovers ERC20 tokens sent accidentally to the contract
     */
    function recoverToken(address token, address to, uint256 amount) external;

    /// @notice The performance fee to send to feeCollector for a set of reward tokens.
    /// @dev Each fee is represented in basis points.
    function setPerformanceFees(TokenAndAmount[] calldata feeData) external;

    /// @notice Set the address used to collect the Origami performance fees.    
    function setFeeCollector(address _feeCollector) external;

    /// @notice Set whether post processing of the rewards is enabled/disabled
    /// @dev In normal operations this would be false, however if there is an issue
    /// with the post processing (eg something is paused), setting this to true
    /// enables stakers to withdraw and claim rewards.
    function setPostProcessingDisabled(bool value) external;

    /// @notice Set whether the contract is paused for different states
    function setPaused(bool onStake_, bool onWithdraw_, bool onGetReward_) external;

    /// @notice Maximum number of reward tokens that can be supported
    /// @dev Limited to prevent gas issues with reward calculations
    function MAX_NUM_REWARD_TOKENS() external view returns (uint256);

    /// @notice The primary reward token for this vault
    function primaryRewardToken() external view returns (address);

    /// @notice Fee collector
    function feeCollector() external view returns (address);

    /// @notice The swapper contract responsible for swapping reward tokens into the base asset.
    /// @dev Only required to be set if the underlying vault has more than just the primaryRewardToken as rewards
    function swapper() external view returns (address);
    
    /// @notice Performance fees (in basis points) as a fraction of the ibgt tokens reinvested.
    function performanceFeeBps(address rewardToken) external view returns (uint256);

    /// @notice The maximum possible value for the Origami performance fee
    function MAX_PERFORMANCE_FEE_BPS() external view returns (uint256);

    /// @notice Whether harvestVault() is restricted to elevated access only
    function restrictedPublicHarvest() external view returns (bool);

    /// @notice Whether post processing of the rewards is disabled
    /// @dev In normal operations this would be false, however if there is an issue
    /// with the post processing (eg something is paused), setting this to true
    /// enables stakers to withdraw and claim rewards.
    function postProcessingDisabled() external view returns (bool);

    /// @notice Whether the contract is paused for different states
    function isPaused() external view returns (bool onStake, bool onWithdraw, bool onGetReward);

    /// @notice Returns all reward tokens
    function getAllRewardTokens() external view returns (address[] memory);

    /**
     * @notice Returns all claimable rewards for a user
     * @notice Only up to date since the `lastUpdateTime`
     */
    function getAllRewardsForUser(address _user) external view returns (TokenAndAmount[] memory);

    /// @notice Returns the amount of rewards from the underlying reward vault which 
    /// are yet to be harvested and notified.
    function unharvestedRewards(address rewardToken) external view returns (uint256);

    /**
     * @notice Returns the underlying rewards vault
     */
    function rewardsVault() external view returns (address);

    /// @notice Whether the vault is in 'multi reward mode' or 'single reward mode'
    /// @dev
    ///   - `multi reward mode`: Reward tokens are claimed from the underlying vault and then distributed for claiming
    ///                          (if whitelisted)
    ///   - `single reward mode`: Reward tokens are claimed from the underlying vault. Rewards other than the
    ///                          `rewardTokens[0]` are swapped into more `rewardTokens[0]` prior to distribution
    function isMultiRewardMode() external view returns (bool);
}