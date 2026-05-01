pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/investments/staking/OrigamiAutoStaking.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiAutoStaking } from "contracts/interfaces/investments/staking/IOrigamiAutoStaking.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { MultiRewards } from "contracts/investments/staking/MultiRewards.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";

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
abstract contract OrigamiAutoStaking is
    MultiRewards,
    IOrigamiAutoStaking,
    OrigamiElevatedAccess
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiAutoStaking
    uint256 public constant override MAX_NUM_REWARD_TOKENS = 10;

    /// @inheritdoc IOrigamiAutoStaking
    address public immutable override primaryRewardToken;

    /// @dev The associated Infrared rewards vault
    IMultiRewards internal immutable _rewardsVault;

    /// @inheritdoc IOrigamiAutoStaking
    address public override feeCollector;

    /// @inheritdoc IOrigamiAutoStaking
    address public override swapper;

    /// @inheritdoc IOrigamiAutoStaking
    bool public override restrictedPublicHarvest;

    /// @inheritdoc IOrigamiAutoStaking
    bool public override postProcessingDisabled;

    /// @inheritdoc IOrigamiAutoStaking
    Paused public override isPaused;

    /// @inheritdoc IOrigamiAutoStaking
    mapping (address rewardToken => uint256 feeBps) public override performanceFeeBps;

    /// @dev Owner maintains a balance of 1 to recover rewards in periods where there is no stake
    uint256 private constant INITIAL_BALANCE = 1;

    /// @inheritdoc IOrigamiAutoStaking
    uint256 public constant override MAX_PERFORMANCE_FEE_BPS = 100; // 1%

    /// @dev struct to avoid stack too deep
    struct ConstructorArgs {
        address initialOwner;
        address stakingToken;
        address primaryRewardToken;
        address rewardsVault;
        uint256 primaryPerformanceFeeBps;
        address feeCollector;
        uint256 rewardsDuration;
        address swapper;
    }

    constructor(ConstructorArgs memory args)
        MultiRewards(args.stakingToken)
        OrigamiElevatedAccess(args.initialOwner)
    {
        if (args.rewardsDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();

        feeCollector = args.feeCollector;
        primaryRewardToken = args.primaryRewardToken;
        swapper = args.swapper;

        // set rewards vault for staking token
        _rewardsVault = IMultiRewards(args.rewardsVault);
        if (args.stakingToken != _rewardsVault.stakingToken()) revert CommonEventsAndErrors.InvalidAddress(args.stakingToken);
        IERC20(args.stakingToken).safeApprove(args.rewardsVault, type(uint256).max);

        _addRewardWithFee(args.primaryRewardToken, args.rewardsDuration, args.primaryPerformanceFeeBps);

        // To be able to recover rewards which where distributed during periods where there was no stake
        // initialOwner will have a stake of 1 wei in the vault which cannot be withdrawn
        _totalSupply = _balances[args.initialOwner] = INITIAL_BALANCE;
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST & CALLBACKS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOrigamiAutoStaking
    function harvestVault() external override {
        // Public harvest can be restricted, in order to control when rewards
        // are notified. In that case, onlyElevatedAccess is used.
        if (restrictedPublicHarvest && !isElevatedAccess(msg.sender, msg.sig)) {
            revert CommonEventsAndErrors.InvalidAccess();
        }

        _harvestAndNotifyRewards();
    }

    /// @inheritdoc IOrigamiSwapCallback
    function swapCallback() external override nonReentrant {
        // Upon successful fills, the swapper will call this function to automatically reinvest the proceeds.
        if (msg.sender != address(swapper)) revert CommonEventsAndErrors.InvalidAccess();
        _harvestAndNotifyRewards();
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Accept the role as new owner
     * @dev Transfer the initial balance to the new owner
     */
    function acceptOwner() public override {
        _balances[owner] -= INITIAL_BALANCE;
        super.acceptOwner();
        _balances[owner] += INITIAL_BALANCE;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function updateRewardsDuration(
        address _rewardsToken,
        uint256 _rewardsDuration
    ) external override onlyElevatedAccess {
        _setRewardsDuration(_rewardsToken, _rewardsDuration);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function addReward(
        address _rewardsToken,
        uint256 _rewardsDuration,
        uint256 _performanceFeeBps
    ) public virtual override onlyElevatedAccess {
        if (_rewardsToken == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        if (_rewardsDuration == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (rewardData[_rewardsToken].rewardsDuration != 0) revert RewardAlreadyExists();

        // In case the reward token was removed and then re-added, ensure the balance is enough 
        // to cover any existing unclaimed rewards.
        if (IERC20(_rewardsToken).balanceOf(address(this)) < totalUnclaimedRewards[_rewardsToken]) {
            revert CommonEventsAndErrors.InvalidAmount(_rewardsToken, totalUnclaimedRewards[_rewardsToken]);
        }

        if (rewardTokens.length == MAX_NUM_REWARD_TOKENS) revert MaxNumberOfRewards();
        _addRewardWithFee(_rewardsToken, _rewardsDuration, _performanceFeeBps);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function removeReward(address _rewardsToken) external override onlyElevatedAccess {
        // Removing the `primaryRewardToken` from the rewards is not allowed
        if (_rewardsToken == primaryRewardToken) revert CommonEventsAndErrors.InvalidToken(_rewardsToken);
        _removeReward(_rewardsToken);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setSwapper(address _swapper) external override onlyElevatedAccess {
        emit SwapperSet(_swapper);
        swapper = _swapper;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setRestrictedPublicHarvest(bool value) external override onlyElevatedAccess {
        emit RestrictedPublicHarvestSet(value);
        restrictedPublicHarvest = value;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function notifyRewardAmount(address _rewardToken, uint256 _reward) external override onlyElevatedAccess {
        if (_reward == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (rewardData[_rewardToken].rewardsDuration == 0) revert RewardDoesntExist();
        IERC20(_rewardToken).safeTransferFrom(msg.sender, address(this), _reward);

        _harvestAndNotifyRewards();
    }

    /// @inheritdoc IOrigamiAutoStaking
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        _recoverERC20(to, token, amount);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setPerformanceFees(TokenAndAmount[] calldata feeData) external override onlyElevatedAccess {
        // Ensure previous fees are collected before updating
        _harvestAndNotifyRewards();

        TokenAndAmount calldata feeItem;
        for (uint256 i; i < feeData.length; ++i) {
            feeItem = feeData[i];
            _validateFee(feeItem.amount);
            emit PerformanceFeesSet(feeItem.token, feeItem.amount);
            performanceFeeBps[feeItem.token] = feeItem.amount;
        }
    }

    function _validateFee(uint256 fee) internal pure {
        if (fee > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setPostProcessingDisabled(bool value) external override onlyElevatedAccess {
        emit PostProcessingDisabledSet(value);
        postProcessingDisabled = value;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function setPaused(bool onStake_, bool onWithdraw_, bool onGetReward_) external override onlyElevatedAccess {
        emit PausedSet(onStake_, onWithdraw_, onGetReward_);
        isPaused = Paused(onStake_, onWithdraw_, onGetReward_);
    }

    /*//////////////////////////////////////////////////////////////
                            Getters
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOrigamiAutoStaking
    function getAllRewardTokens() external view override returns (address[] memory) {
        return rewardTokens;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function getAllRewardsForUser(
        address _user
    ) external view override returns (TokenAndAmount[] memory) {
        uint256 len = rewardTokens.length;
        TokenAndAmount[] memory tempRewards = new TokenAndAmount[](len);
        uint256 count;
        for (uint256 i; i < len; i++) {
            uint256 amount = earned(_user, rewardTokens[i]);
            if (amount > 0) {
                tempRewards[count] = TokenAndAmount({token: rewardTokens[i], amount: amount});
                count++;
            }
        }

        // Create a new array with the exact size of non-zero rewards
        TokenAndAmount[] memory userRewards = new TokenAndAmount[](count);
        for (uint256 j; j < count; j++) {
            userRewards[j] = tempRewards[j];
        }

        return userRewards;
    }

    /// @inheritdoc IOrigamiAutoStaking
    function unharvestedRewards(address rewardToken) external view override returns (uint256) {
        // Note: The pure MultiRewards doesn't offer a way to get all the reward tokens onchain in one go.
        // The Infrared vault does, but this is intentionally kept generic for other vaults.
        // multicall can be used to get the earned amounts for multiple tokens in one call.
        return _rewardsVault.earned(address(this), rewardToken);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function rewardsVault() external view override returns (address) {
        return address(_rewardsVault);
    }

    /// @inheritdoc IOrigamiAutoStaking
    function isMultiRewardMode() public view returns (bool) {
        return swapper == address(0);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL CALLBACKS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restakes tokens into the underlying vault and then claims and
    /// processes rewards
    function onStake(uint256 amount) internal override {
        if (isPaused.onStake) revert CommonEventsAndErrors.IsPaused();

        // Stake tokens into the underlying rewards vault
        _rewardsVault.stake(amount);
        _claimAndProcessRewards();
    }

    /// @notice Claims and processes rewards before withdrawing tokens from
    /// the underlying vault
    function onWithdraw(uint256 amount) internal override {
        if (isPaused.onWithdraw) revert CommonEventsAndErrors.IsPaused();

        _claimAndProcessRewards();
        _rewardsVault.withdraw(amount);

        // The owner cannot withdraw the initial balance amount
        if (msg.sender == owner && _balances[msg.sender] < INITIAL_BALANCE) revert CommonEventsAndErrors.InvalidParam();
    }

    /// @notice hook called prior to the reward being claimed to harvest the rewards
    /// from the underlying vault
    function onReward() internal override {
        if (isPaused.onGetReward) revert CommonEventsAndErrors.IsPaused();

        _claimAndProcessRewards();
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _addRewardWithFee(
        address _rewardsToken,
        uint256 _rewardsDuration,
        uint256 _performanceFeeBps
    ) internal {
        _addReward(_rewardsToken, _rewardsDuration);
        _validateFee(_performanceFeeBps);
        performanceFeeBps[_rewardsToken] = _performanceFeeBps;
    }

    /// @dev Implementations define how to process the claimed rewards from the underlying rewards vault
    /// and allocate into the `primaryRewardToken`
    /// eg deposit iBGT into oriBGT in the case of infrared auto-stakers
    function _postProcessClaimedRewards() internal virtual returns (uint256 primaryRewardTokenAmount);

    /// @dev Claim rewards from the underlying reward vault and process
    function _claimAndProcessRewards() private {
        // Claim rewards from the underlying vault
        _rewardsVault.getReward();

        // Process any claimed rewards which contribute to the `primaryRewardToken`
        // in order to get any effects of compounding as soon as possible.
        // In case this reverts (eg paused)
        if (!postProcessingDisabled) {
            _postProcessClaimedRewards();
        }
    }

    /// @dev Claim and process rewards from underlying reward vault
    /// and then notify for new rewards.
    /// Note: Donations are allowed
    function _harvestAndNotifyRewards() private {
        _claimAndProcessRewards();

        uint256 rewardBalance;
        uint256 numRewardTokens = rewardTokens.length;
        address rewardToken;
        address _swapper = swapper;
        uint256 totalUnclaimed;
        for (uint256 i; i < numRewardTokens; ++i) {
            rewardToken = rewardTokens[i];
            rewardBalance = IERC20(rewardToken).balanceOf(address(this));
            totalUnclaimed = totalUnclaimedRewards[rewardToken];
            if (rewardBalance <= totalUnclaimed) continue;

            // The amount to distribute is the current balance minus any total unclaimed
            // amounts
            rewardBalance -= totalUnclaimed;

            // Always distribute if the reward token is the primary, otherwise only if
            // in Multi-Reward mode (the swapper is address(0))
            if (rewardToken == primaryRewardToken || _swapper == address(0)) {
                // Collect performance fees before distributing
                _notifyRewardAmount(rewardToken, _chargePerformanceFee(rewardToken, rewardBalance));
            } else {
                // If in Single-Reward mode, those tokens are sent to the swapper
                // for conversion back to the primaryRewardToken
                IERC20(rewardToken).safeTransfer(_swapper, rewardBalance);
            }
        }
    }

    function _chargePerformanceFee(address rewardToken, uint256 amount) private returns (uint256 amountForDistribution) {
        uint256 feeForOrigami;
        (amountForDistribution, feeForOrigami) = amount.splitSubtractBps(
            performanceFeeBps[rewardToken],
            OrigamiMath.Rounding.ROUND_DOWN
        );

        if (feeForOrigami > 0) {
            emit PerformanceFeesCollected(feeForOrigami);
            IERC20(rewardToken).safeTransfer(feeCollector, feeForOrigami);
        }
    }
}
