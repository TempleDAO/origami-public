pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/infrared/IOrigamiInfraredVaultProxy.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";
import { IMultiRewards } from "contracts/interfaces/external/staking/IMultiRewards.sol";

/**
 * @title Origami Infrared Vault Proxy
 * @notice Stake/withdraw into Infrared Vault to earn iBGT and other reward tokens
 */
interface IOrigamiInfraredVaultProxy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              PERMISSIONED WRITE FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @notice Stakes tokens into the vault
    /// @dev Assumes the caller has already transferred `amount` of staking tokens to this contract.
    function stake(uint256 amount) external;

    /// @notice Withdraws the `amount` of staked tokens from the vault and sends to the recipient
    function withdraw(uint256 amount, address recipient) external;

    /// @notice Withdraws all staked tokens and claims pending rewards
    /// @dev Combines withdraw and getRewards operations
    function exit(address recipient) external;

    /// @notice Claims all pending rewards for the caller
    /// @dev Transfers all accrued rewards to the recipient
    function getRewards(address recipient) external;

    /// @notice Recover any other token.
    function recoverToken(address token, address to, uint256 amount) external;

    /// @notice Set the allowance of any token spend
    function setTokenAllowance(address token, address spender, uint256 amount) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    
    /// @notice The rewards vault that this contract stakes into to earn rewards
    function infraredVault() external view returns (IInfraredVault);

    /// @notice The token that users stake to earn rewards
    function stakingToken() external view returns (IERC20);

    /// @notice Returns all reward tokens
    function getAllRewardTokens() external view returns (address[] memory);

    /// @notice Returns all rewards for this contract
    function unclaimedRewards() external view returns (IInfraredVault.UserReward[] memory);

    /// @notice Calculates the total reward for the duration of each of the rewards tokens
    function getRewardsForDuration() external view returns (uint256[] memory);

    /// @notice Calculates the reward per token for each of the rewards tokens
    function getRewardsPerToken() external view returns (uint256[] memory);

    /// @notice Gets the reward data for each of the rewards tokens
    function rewardsData() external view returns (IMultiRewards.Reward[] memory);
    
    /// @notice Returns the total amount of staked tokens in the contract
    function totalSupply() external view returns (uint256);

    /// @notice The current balance of the stake token of this contract in the rewards vault
    function stakedBalance() external view returns (uint256);

    /// @notice Returns the Infrared protocol coordinator
    function infrared() external view returns (address);

    /// @notice Returns the associated Berachain rewards vault
    function rewardsVault() external view returns (IBeraRewardsVault);
}
