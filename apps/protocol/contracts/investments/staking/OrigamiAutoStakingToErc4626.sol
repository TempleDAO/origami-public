pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (contracts/investments/staking/OrigamiAutoStakingToErc4626.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OrigamiAutoStaking } from "contracts/investments/staking/OrigamiAutoStaking.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Auto-Staking (to ERC4626)
 * @notice An Origami Auto-Staking vault which claims tokens from the underlying rewards vault, then deposits
 * into an ERC4626 vault which is the primary token paid out to users. 
 * Eg claim iBGT from Infrared and then deposit into oriBGT
 * Secondary reward tokens are either paid out directly (multi-reward mode) or swapped into more primary rewards (single-reward mode)
 */
contract OrigamiAutoStakingToErc4626 is OrigamiAutoStaking {
    using SafeERC20 for IERC20;

    /// @notice The primary ERC20 which is claimed from the underlying reward vault
    IERC20 public immutable underlyingPrimaryRewardToken;

    constructor(
        OrigamiAutoStaking.ConstructorArgs memory args,
        address underlyingPrimaryRewardToken_
    ) OrigamiAutoStaking(args) {
        underlyingPrimaryRewardToken = IERC20(underlyingPrimaryRewardToken_);
        underlyingPrimaryRewardToken.safeApprove(args.primaryRewardToken, type(uint256).max);
    }

    /// @inheritdoc OrigamiAutoStaking
    function addReward(
        address _rewardsToken,
        uint256 _rewardsDuration,
        uint256 _performanceFeeBps
    ) public override onlyElevatedAccess {
        // Don't allow the underlying primary reward token to be a valid reward token
        // as this is always compounded directly into the `primaryRewardToken`
        if (_rewardsToken == address(underlyingPrimaryRewardToken)) revert CommonEventsAndErrors.InvalidToken(_rewardsToken);
        super.addReward(_rewardsToken, _rewardsDuration, _performanceFeeBps);
    }

    /// @dev Use the claimed primary rewards from the underling rewards vault, to deposit into 
    /// an ERC4626 vault for distribution to users as the `primaryRewardToken`
    function _postProcessClaimedRewards() internal override returns (uint256 primaryRewardTokenAmount) {
        uint256 rewardBalance = underlyingPrimaryRewardToken.balanceOf(address(this));
        IERC4626 primaryRewardToken4626 = IERC4626(address(primaryRewardToken));
        if (rewardBalance > 0) {
            primaryRewardTokenAmount = primaryRewardToken4626.deposit(rewardBalance, address(this));
        }
    }
}
