pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/erc4626/IOrigamiErc4626WithRewardsManager.sol)

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IMerklDistributor } from "contracts/interfaces/external/merkl/IMerklDistributor.sol";
import { IMorphoUniversalRewardsDistributor } from "contracts/interfaces/external/morpho/IMorphoUniversalRewardsDistributor.sol";

import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";
import { IOrigamiVestingReserves } from "contracts/interfaces/investments/IOrigamiVestingReserves.sol";

/**
 * @title Origami Vault Manager for ERC4626 deposits + merkl/morpho rewards
 * @notice A manager for auto-compounding strategies on ERC-4626 vaults, where rewards can be claimed
 * from Merkl or Morpho rewards distributors
 * 
 * @dev
 *  - Morpho rewards distributor: https://github.com/morpho-org/universal-rewards-distributor/blob/v1.0.0/src/UniversalRewardsDistributor.sol
 *  - Merkl rewards distributor: https://github.com/AngleProtocol/merkl-contracts/blob/43ae80ea64834a2792421f1eb09350c36cabee17/contracts/Distributor.sol
 * 
 * Rewards are claimed, swapped into the deposit asset, and reinvested
 * New assets for the vault are dripped over a period of time rather than instantaneously
 *
 * Constraints on the underlying ERC4626 vault:
 *  - There must not be deposit or exit fees on the underyling vault
 *  - In order to upgrade the manager in OrigamiDelegated4626Vault::setManager() all remaining assets must be able 
 *    to be withdrawn in one single transaction
 */
interface IOrigamiErc4626WithRewardsManager is 
    IOrigamiCompoundingVaultManager,
    IOrigamiSwapCallback,
    IOrigamiVestingReserves
{
    event RewardTokensSet();
    event MerklRewardsDistributorSet(address indexed distributor);
    event MorphoRewardsDistributorSet(address indexed distributor);

    /// @notice Update reserves vesting duration which linearly drips in rewards over
    /// a number of seconds
    function setReservesVestingDuration(uint48 durationInSeconds) external;

    /// @notice Set the expected reward tokens
    function setRewardTokens(address[] calldata newRewardTokens) external;

    /// @notice Set the Merkl.io rewards distributor
    function setMerklRewardsDistributor(address distributor) external;

    /// @notice Set the Morpho rewards distributor
    function setMorphoRewardsDistributor(address distributor) external;

    /// @notice Toggles whitelisting an operator to claim rewards, for a given Merkl distributor
    function merklToggleOperator(address operator) external;

    /// @notice Set a withdrawal fee imposed on those leaving the vault
    function setWithdrawalFee(uint16 feeBps) external;

    /// @notice Set the performance fee for Origami
    /// @dev Fees cannot increase
    /// Fees are collected on the `asset` token when `reinvest()` is called
    function setPerformanceFees(uint16 origamiFeeBps) external;

    /// @notice Claim rewards from Merkl and immediately call reinvest, which
    /// also sends the claimed rewards to the swapper
    function merklClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    /// @notice Claim rewards from Morpho and immediately call reinvest, which
    /// also sends the claimed rewards to the swapper
    function morphoClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    /// @notice The maximum possible value for the retention bonus on withdrawals
    function MAX_WITHDRAWAL_FEE_BPS() external view returns (uint16);

    /// @notice The maximum possible value for the performance fee, taken on the underlying assets
    function MAX_PERFORMANCE_FEE_BPS() external view returns (uint16);

    /// @notice The underlying ERC4626 vault earning yield
    function underlyingVault() external view returns (IERC4626);

    /// @notice The Merkl rewards distributor
    function merklRewardsDistributor() external view returns (IMerklDistributor);

    /// @notice The Morpho rewards distributor
    function morphoRewardsDistributor() external view returns (IMorphoUniversalRewardsDistributor);

    /// @notice The amount of assets staked in the underlying vault
    function depositedAssets() external view returns (uint256);
}
