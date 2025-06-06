pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/bera/IOrigamiBeraRewardsVaultProxy.sol)

import { IBeraRewardsVault } from "contracts/interfaces/external/bera/IBeraRewardsVault.sol";

/**
 * @title Origami Berachain Rewards Vault Proxy
 * @notice Stake/withdraw from Berachain Reward Vaults to earn BGT
 */
interface IOrigamiBeraRewardsVaultProxy {
    /**
     * @notice Recover any token
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external;

    /**
     * @notice Set the allowance of any token spend
     */
    function setTokenAllowance(address token, address spender, uint256 amount) external;

    /**
     * @notice Set another address to claim and manage the rewards.
     */
    function setOperator(address operator) external;

    /**
     * @notice Stake tokens in the vault.
     * @dev Assumes the caller has already transferred `amount` of staking tokens to this contract.
     */
    function stake(uint256 amount) external;

    /**
     * @notice Withdraw the `amount` of staked tokens from the vault and sends to the recipient
     */
    function withdraw(
        uint256 amount,
        address recipient
    ) external;

    /**
     * @notice Stake tokens on behalf of another account.
     */
    function delegateStake(address account, uint256 amount) external;

    /**
     * @notice Withdraw tokens staked on behalf of another account by the delegate (msg.sender).
     */
    function delegateWithdraw(
        address account,
        uint256 amount,
        address recipient
    ) external;

    /**
     * @notice Exit the vault with the staked tokens and claim the reward.
     * Reward tokens (including BGT) can be sent to recipient
     * @dev Be very careful on who the recipient is, as BGT is non-transferrable.
     */
    function exit(
        address recipient
    ) external;

    /**
     * @notice Claim the reward and send to a recipient.
     * @dev Be very careful on who the recipient is, as BGT is non-transferrable.
     */
    function getReward(
        address recipient
    ) external;

    /**
     * @notice The rewards vault that this contract stakes into to earn rewards
     */
    function rewardsVault() external view returns (IBeraRewardsVault);

    /**
     * @notice The current balance of the stake token of this contract in the rewards vault
     */
    function stakedBalance() external view returns (uint256);

    /**
     * @notice The current balance of the rewards vault reward token for this contract
     */
    function unclaimedRewardsBalance() external view returns (uint256);
}
