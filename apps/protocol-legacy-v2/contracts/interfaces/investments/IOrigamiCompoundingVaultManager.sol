pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiCompoundingVaultManager.sol)

import {IOrigamiDelegated4626VaultManager} from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";

/**
 * @title Origami Auto-Compounding Vault Manager
 * @notice Handles vault strategies where farmed rewards are reinvested into the same vault after
 * being converted to the base asset.
 */
interface IOrigamiCompoundingVaultManager is IOrigamiDelegated4626VaultManager {
    event AssetStaked(uint256 amount);
    event AssetWithdrawn(uint256 amount);
    event SwapperSet(address indexed newSwapper);
    event ClaimedReward(
        address indexed rewardToken, 
        uint256 amountForCaller,
        uint256 amountForOrigami,
        uint256 amountForVault
    );

    /**
     * @notice Set the address used to collect the Origami performance fees.
     */
    function setFeeCollector(address _feeCollector) external;

    /**
     * @notice Set the swapper contract responsible for swapping reward tokens to the base asset.
     */
    function setSwapper(address _swapper) external;

    /**
     * @notice A permissionless function to claim rewards from the underlying farmed vault.
     * - The caller can nominate an address to receive a portion of these rewards (to compensate for gas).
     * - Origami will earn a portion of these rewards (as a performance fee).
     * - The remainder is sent to a swapper contract to be converted to the base asset.
     * Base asset proceeds from the swapper will sent back to this contract ready to add to the vault on the next deposit.
     */
    function harvestRewards(address incentivesReceiver) external;

    /**
     * @notice Reinvest harvested rewards currently held by this contract
     * - For non-vault asset reward tokens, this may initiate swaps from reward tokens to the vault asset
     * - For vault asset reward tokens, this may allocate those tokens into the underlying protocol to get yield.
     * - Protocol performance fees may be taken.
     */
    function reinvest() external;

    /**
     * @notice List the rewards being distributed by the underlying farmed vault.
     */
    function getAllRewardTokens() external view returns (address[] memory);

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The swapper contract responsible for swapping reward tokens into the base asset.
     */
    function swapper() external view returns (address);
}
