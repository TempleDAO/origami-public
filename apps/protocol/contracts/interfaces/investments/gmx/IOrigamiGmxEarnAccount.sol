pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/gmx/IOrigamiGmxEarnAccount.sol)

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IOrigamiGmxEarnAccount {
    // Input parameters required when claiming/compounding rewards from GMX.io
    struct HandleGmxRewardParams {
        bool shouldClaimGmx;
        bool shouldStakeGmx;
        bool shouldClaimEsGmx;
        bool shouldStakeEsGmx;
        bool shouldStakeMultiplierPoints;
        bool shouldClaimWeth;
    }

    // Rewards that Origami claimed from GMX.io
    struct ClaimedRewards {
        uint256 wrappedNativeFromGmx;
        uint256 wrappedNativeFromGlp;
        uint256 esGmxFromGmx;
        uint256 esGmxFromGlp;
        uint256 vestedGmx;
    }

    enum VaultType {
        GLP,
        GMX
    }

    /// @notice The current wrappedNative and esGMX rewards per second
    /// @dev This includes any boost to wrappedNative (ie ETH/AVAX) from staked multiplier points.
    /// @param vaultType If for GLP, get the reward rates for just staked GLP rewards. If GMX get the reward rates for combined GMX/esGMX/mult points
    /// for Origami's share of the upstream GMX.io rewards.
    function rewardRates(VaultType vaultType) external view returns (uint256 wrappedNativeTokensPerSec, uint256 esGmxTokensPerSec);

    /// @notice The amount of $esGMX and $Native (ETH/AVAX) which are claimable by Origami as of now
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX get the reward rates for combined GMX/esGMX/mult points
    /// @dev This is composed of both the staked GMX and staked GLP rewards that this account may hold
    function harvestableRewards(VaultType vaultType) external view returns (
        uint256 wrappedNativeAmount, 
        uint256 esGmxAmount
    );

    /// @notice Harvest all rewards, and apply compounding:
    /// - Claim all wrappedNative and send to origamiGmxManager
    /// - Claim all esGMX and:
    ///     - Deposit a portion into vesting (given by `esGmxVestingRate`)
    ///     - Stake the remaining portion
    /// - Claim all GMX from vested esGMX and send to origamiGmxManager
    /// - Stake/compound any multiplier point rewards (aka bnGmx) 
    /// @dev only the OrigamiGmxManager can call since we need to track and action based on the amounts harvested.
    function harvestRewards(uint256 _esGmxVestingRate) external returns (ClaimedRewards memory claimedRewards);

    /// @notice Pass-through handleRewards() for harvesting/compounding rewards.
    function handleRewards(HandleGmxRewardParams calldata params) external returns (ClaimedRewards memory claimedRewards);

    /// @notice Stake any $GMX that this contract holds at GMX.io
    function stakeGmx(uint256 _amount) external;

    /// @notice Unstake $GMX from GMX.io and send to the operator
    /// @dev This will burn any aggregated multiplier points, so should be avoided where possible.
    function unstakeGmx(uint256 _maxAmount) external;

    /// @notice Buy and stake $GLP using GMX.io's contracts using a whitelisted token.
    /// @dev GMX.io takes fees dependent on the pool constituents.
    function mintAndStakeGlp(
        uint256 fromAmount,
        address fromToken,
        uint256 minUsdg,
        uint256 minGlp
    ) external returns (uint256);

    /// @notice Unstake and sell $GLP using GMX.io's contracts, to a whitelisted token.
    /// @dev GMX.io takes fees dependent on the pool constituents.
    function unstakeAndRedeemGlp(
        uint256 glpAmount, 
        address toToken, 
        uint256 minOut, 
        address receiver
    ) external returns (uint256);

    /// @notice Transfer staked $GLP to another receiver. This will unstake from this contract and restake to another user.
    function transferStakedGlp(uint256 glpAmount, address receiver) external;

    /// @notice Attempt to transfer staked $GLP to another receiver. This will unstake from this contract and restake to another user.
    /// @dev If the transfer cannot happen in this transaction due to the GLP cooldown
    /// then future GLP deposits will be paused such that it can be attempted again.
    /// When the transfer succeeds in the future, deposits will be unpaused.
    function transferStakedGlpOrPause(uint256 glpAmount, address receiver) external;

    /// @notice The GMX contract which can transfer staked GLP from one user to another.
    function stakedGlp() external view returns (IERC20Upgradeable);

    /// @notice When this contract is free to exit a GLP position, a cooldown period after the latest GLP purchase
    function glpInvestmentCooldownExpiry() external view returns (uint256);

    /// @notice The last timestamp that staked GLP was transferred out of this account.
    function glpLastTransferredAt() external view returns (uint256);

    /// @notice Whether GLP purchases are currently paused
    function glpInvestmentsPaused() external view returns (bool);
}