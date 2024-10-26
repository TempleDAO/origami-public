pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/erc4626/IOrigamiDelegated4626VaultManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { DynamicFees } from "contracts/libraries/DynamicFees.sol";

/** 
 * @title Origami Delegated ERC4626 Vault Manager
 * @notice An Origami ERC4626 Vault Manager, which handles the deposited assets from a
 * IOrigamiDelegated4626Vault
 */
interface IOrigamiDelegated4626VaultManager is IERC165 {
    event FeeBpsSet(uint16 depositFeeBps, uint16 withdrawalFeeBps);
    event InKindFees(DynamicFees.FeeType feeType, uint256 feeBps, uint256 feeAmount);
    event FeeCollectorSet(address indexed feeCollector);

    /// @notice Deposit tokens into the underlying protocol
    /// @dev Implementation may assume the tokens have already been sent to this contract
    /// type(uint256).max is accepted, meaning the entire balance
    function deposit(uint256 assetsAmount) external returns (
        uint256 assetsDeposited
    );

    /// @notice Withdraw tokens from the underlying protocol to a given receiver
    /// @dev
    /// - Fails if it can't withdraw that amount
    /// - type(uint256).max is accepted, meaning the entire balance
    function withdraw(
        uint256 assetsAmount,
        address receiver
    ) external returns (uint256 assetsWithdrawn);

    /// @notice The Origami vault this is managing
    function vault() external view returns (IOrigamiDelegated4626Vault);

    /// @notice Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
    /// @dev
    /// - MUST be an ERC-20 token contract.
    /// - MUST NOT revert.
    function asset() external view returns (address assetTokenAddress);

    /// @notice Returns the total amount of the underlying asset that is “managed” by Vault.
    /// @dev
    /// - SHOULD include any compounding that occurs from yield.
    /// - MUST be inclusive of any fees that are charged against assets in the Vault.
    /// - MUST NOT revert.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Whether deposits and mints are currently paused
    function areDepositsPaused() external view returns (bool);

    /// @notice Whether withdrawals and redemptions are currently paused
    function areWithdrawalsPaused() external view returns (bool);
}
