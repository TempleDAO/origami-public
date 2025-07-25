pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/infrared/IOrigamiInfraredVaultManager.sol)

import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";
import { IOrigamiVestingReserves } from "contracts/interfaces/investments/IOrigamiVestingReserves.sol";

/**
 * @title Origami Infrared Vault Manager
 * @notice A manager for auto-compounding strategies on Infrared Vaults that handles staking of user
 * deposits and restaking of claimed rewards.
 */
interface IOrigamiInfraredVaultManager is 
    IOrigamiCompoundingVaultManager,
    IOrigamiSwapCallback,
    IOrigamiVestingReserves
{
    event PerformanceFeesCollected(uint256 amount);

    /// @notice Set a withdrawal fee imposed on those leaving the vault
    function setWithdrawalFee(uint16 feeBps) external;

    /// @notice Set the performance fee for Origami
    /// @dev Fees cannot increase
    /// Fees are collected on the `asset` token when `reinvest()` is called
    function setPerformanceFees(uint16 origamiFeeBps) external;

    /// @notice The maximum possible value for the retention bonus on withdrawals
    function MAX_WITHDRAWAL_FEE_BPS() external view returns (uint16);

    /// @notice The maximum possible value for the Origami performance fee
    function MAX_PERFORMANCE_FEE_BPS() external view returns (uint16);

    /// @notice The underlying infrared reward vault
    function rewardVault() external view returns (IInfraredVault);

    /// @notice The tally of all claimable rewards from the infrared vault
    function unclaimedRewards() external view returns (IInfraredVault.UserReward[] memory);

    /// @notice The amount of assets staked in the infrared vault
    function stakedAssets() external view returns (uint256);

    /// @notice Duration of each vesting period
    /// @dev Same as reservesVestingDuration() in IOrigamiVestingReserves,
    /// added for interface backwards compatibility
    function RESERVES_VESTING_DURATION() external view returns (uint48);
}
