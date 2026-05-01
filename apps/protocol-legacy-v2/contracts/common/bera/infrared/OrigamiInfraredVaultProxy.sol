pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/infrared/OrigamiInfraredVaultProxy.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { IOrigamiInfraredVaultProxy } from "contracts/interfaces/common/bera/infrared/IOrigamiInfraredVaultProxy.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Infrared Vault Proxy
 * @notice Stake/withdraw tokens in Infrared Vaults to earn iBGT and other reward tokens
 */
contract OrigamiInfraredVaultProxy is IOrigamiInfraredVaultProxy, OrigamiElevatedAccess {
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiInfraredVaultProxy
    IInfraredVault public immutable override infraredVault;

    /// @inheritdoc IOrigamiInfraredVaultProxy
    IERC20 public immutable override stakingToken;

    constructor(address initialOwner_, address infraredVault_) OrigamiElevatedAccess(initialOwner_) {
        infraredVault = IInfraredVault(infraredVault_);
        stakingToken = IERC20(infraredVault.stakingToken());

        // Grant max approval for the staking token.
        stakingToken.forceApprove(infraredVault_, type(uint256).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              PERMISSIONED WRITE FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @inheritdoc IOrigamiInfraredVaultProxy
    function stake(uint256 amount) external override onlyElevatedAccess {
        // This assumes:
        //  - The caller has already transferred the staking token to this contract.
        //  - setTokenAllowance has been set on this contract ahead of time
        return infraredVault.stake(amount);
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function withdraw(uint256 amount, address recipient) external override onlyElevatedAccess {
        if (amount == 0) revert CommonEventsAndErrors.ExpectedNonZero();
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        infraredVault.withdraw(amount);
        stakingToken.safeTransfer(recipient, amount);
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function exit(address recipient) external override onlyElevatedAccess {
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        infraredVault.exit();

        // Transfer the staking token to the recipient
        uint256 balance = stakingToken.balanceOf(address(this));
        if (balance > 0) {
            stakingToken.safeTransfer(recipient, balance);
        }

        // Transfer any reward tokens to the recipient
        _transferRewards(recipient);
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function getRewards(address recipient) external override onlyElevatedAccess {
        if (recipient == address(0)) revert CommonEventsAndErrors.InvalidAddress(recipient);

        infraredVault.getReward();
        _transferRewards(recipient);
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function recoverToken(address token, address to, uint256 amount) external override onlyElevatedAccess {
        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function setTokenAllowance(address token, address spender, uint256 amount) external override onlyElevatedAccess {
        IERC20 _token = IERC20(token);
        if (amount == _token.allowance(address(this), spender)) return;
        _token.forceApprove(spender, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @inheritdoc IOrigamiInfraredVaultProxy
    function getAllRewardTokens() public override view returns (address[] memory) {
        return infraredVault.getAllRewardTokens();
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function unclaimedRewards() external override view returns (IInfraredVault.UserReward[] memory) {
        return infraredVault.getAllRewardsForUser(address(this));
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function getRewardsForDuration() external override view returns (uint256[] memory rewardsForDuration) {
        address[] memory rewardTokens = getAllRewardTokens();
        rewardsForDuration = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardsForDuration[i] = infraredVault.getRewardForDuration(rewardTokens[i]);
        }
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function getRewardsPerToken() external override view returns (uint256[] memory rewardsPerToken) {
        address[] memory rewardTokens = getAllRewardTokens();
        rewardsPerToken = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardsPerToken[i] = infraredVault.rewardPerToken(rewardTokens[i]);
        }
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function rewardsData() external override view returns (IMultiRewards.Reward[] memory data) {
        address[] memory rewardTokens = getAllRewardTokens();
        data = new IMultiRewards.Reward[](rewardTokens.length);

        address rewardsDistributor;
        uint256 rewardsDuration;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 rewardResidual;
        for (uint256 i; i < rewardTokens.length; ++i) {
            (
                rewardsDistributor,
                rewardsDuration,
                periodFinish,
                rewardRate,
                lastUpdateTime,
                rewardPerTokenStored,
                rewardResidual
            ) = infraredVault.rewardData(rewardTokens[i]);

            data[i] = IMultiRewards.Reward(
                rewardsDistributor,
                rewardsDuration,
                periodFinish,
                rewardRate,
                lastUpdateTime,
                rewardPerTokenStored,
                rewardResidual
            );
        }
    }
    
    /// @inheritdoc IOrigamiInfraredVaultProxy
    function totalSupply() external override view returns (uint256) {
        return infraredVault.totalSupply();
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function stakedBalance() external override view returns (uint256) {
        return infraredVault.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function infrared() external override view returns (address) {
        return infraredVault.infrared();
    }

    /// @inheritdoc IOrigamiInfraredVaultProxy
    function rewardsVault() external override view returns (IBeraRewardsVault) {
        return IBeraRewardsVault(infraredVault.rewardsVault());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    function _transferRewards(address recipient) private {
        address[] memory rewardTokens = getAllRewardTokens();
        IERC20 rewardToken;
        uint256 balance;
        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardToken = IERC20(rewardTokens[i]);
            balance = rewardToken.balanceOf(address(this));
            if (balance > 0) {
                rewardToken.safeTransfer(recipient, balance);
            }
        }
    }
}
