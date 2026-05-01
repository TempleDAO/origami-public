pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiDelegated4626Vault.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { ITokenPrices } from "contracts/interfaces/common/ITokenPrices.sol";
import { IOrigamiErc4626 } from "contracts/interfaces/common/IOrigamiErc4626.sol";
import { OrigamiErc4626 } from "contracts/common/OrigamiErc4626.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami 4626 Vault that delegates strategy to a manager.
 * @notice Assets are held and managed by the manager. This vault handles simple shares accounting.
 */
contract OrigamiDelegated4626Vault is
    OrigamiErc4626,
    IOrigamiDelegated4626Vault
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IOrigamiDelegated4626Vault
    ITokenPrices public override tokenPrices;

    /// @dev The manager which handles the investment strategy
    IOrigamiDelegated4626VaultManager internal _manager;

    constructor(
        address initialOwner_,
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        address tokenPrices_
    ) 
        OrigamiErc4626(initialOwner_, name_, symbol_, asset_)
    {
        tokenPrices = ITokenPrices(tokenPrices_);
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function setManager(address newManagerAddress, uint256 minNewAssets) external virtual override onlyElevatedAccess {
        if (newManagerAddress == address(0)) revert CommonEventsAndErrors.InvalidAddress(newManagerAddress);
        IOrigamiDelegated4626VaultManager newManager = IOrigamiDelegated4626VaultManager(newManagerAddress);
        if (address(newManager.vault()) != address(this)) revert CommonEventsAndErrors.InvalidAddress(newManagerAddress);

        IOrigamiDelegated4626VaultManager oldManager = _manager;
        if (address(oldManager) != address(0)) {
            // Pull out all `totalAssets()` from old, and deposit into new.
            // If it's not possible to withdraw `totalAssets()` from the old because they're all allocate and cannot be 
            // withdrawn just-in-time, this is expected to fail. In that case, the assets must be made available to withdraw
            // prior to migration.
            uint256 existingAssets = oldManager.totalAssets();
            uint256 withdrawnAssets = oldManager.withdraw(existingAssets, newManagerAddress);
            newManager.deposit(withdrawnAssets);

            // The totalAssets in the new must be >= the min required
            // It may be slightly less than initially due to underlying rounding. Elevated access will use a reasonable/small
            // slippage to calculate this offchain first.
            uint256 newAssets = newManager.totalAssets();
            if (newAssets < minNewAssets) revert CommonEventsAndErrors.Slippage(minNewAssets, newAssets);
        }

        emit ManagerSet(newManagerAddress);
        _manager = newManager;
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function setTokenPrices(address _tokenPrices) external virtual override onlyElevatedAccess {
        if (_tokenPrices == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit TokenPricesSet(_tokenPrices);
        tokenPrices = ITokenPrices(_tokenPrices);
    }

    /**
     * @notice Emit an event from the vault when the performance fees are updated
     */
    function logPerformanceFeesSet(uint256 performanceFees) external virtual {
        if (msg.sender != address(_manager)) revert CommonEventsAndErrors.InvalidAccess();
        emit PerformanceFeeSet(performanceFees);
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual override(IERC4626, OrigamiErc4626) returns (uint256) {
        return _manager.totalAssets();
    }

    /// @inheritdoc IOrigamiErc4626
    function areDepositsPaused() public virtual override(IOrigamiErc4626, OrigamiErc4626) view returns (bool) {
        return _manager.areDepositsPaused();
    }

    /// @inheritdoc IOrigamiErc4626
    function areWithdrawalsPaused() public virtual override(IOrigamiErc4626, OrigamiErc4626) view returns (bool) {
        return _manager.areWithdrawalsPaused();
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function manager() external virtual override view returns (address) {
        return address(_manager);
    }

    /// @inheritdoc IOrigamiDelegated4626Vault
    function performanceFeeBps() external virtual override view returns (uint48) {
        // Return the total fee for both the caller (to pay for gas) and origami
        (uint48 callerFeeBps, uint48 origamiFeeBps) = _manager.performanceFeeBps();
        return callerFeeBps + origamiFeeBps; 
    }

    /// @dev Pull freshly deposited assets and deposit into the manager
    function _depositHook(address caller, uint256 assets) internal virtual override {
        SafeERC20.safeTransferFrom(_asset, caller, address(_manager), assets);
        _manager.deposit(assets);
    }

    /// @inheritdoc IOrigamiErc4626
    function depositFeeBps() public view virtual override(IOrigamiErc4626, OrigamiErc4626) returns (uint256) {
        return _manager.depositFeeBps();
    }

    /// @dev Pull assets from the manager which also sends to the receiver
    function _withdrawHook(
        uint256 assets,
        address receiver
    ) internal virtual override {
        _manager.withdraw(assets, receiver);
    }

    /// @inheritdoc IOrigamiErc4626
    function withdrawalFeeBps() public view virtual override(IOrigamiErc4626, OrigamiErc4626) returns (uint256) {
        return _manager.withdrawalFeeBps();
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address /*receiver*/) public override(IERC4626, OrigamiErc4626) view returns (uint256 maxAssets) {
        // Minimum of the free capacity given the total supply cap, and from what the 
        // manager reports as the max available to deposit
        uint256 fromTotalSupplyCap = _maxDeposit(depositFeeBps());
        uint256 fromManager = _manager.maxDeposit();
        return fromTotalSupplyCap < fromManager ? fromTotalSupplyCap : fromManager;
    }

    /// @inheritdoc IERC4626
    function maxMint(address /*receiver*/) public virtual override(IERC4626, OrigamiErc4626) view returns (uint256 maxShares) {
        // Minimum of the free capacity given the total supply cap, and from what the 
        // manager reports as the max assets available to deposit
        uint256 fromTotalSupplyCap = _maxMint();
        uint256 maxAssetsfromManager = _manager.maxDeposit();
        if (maxAssetsfromManager == type(uint256).max) return fromTotalSupplyCap;

        // Convert the max number of assets the manager can deposit into shares
        // _previewDeposit() correctly rounds down to the max number of shares
        (uint256 maxSharesFromManager,) = _previewDeposit(
            maxAssetsfromManager,
            depositFeeBps()
        );

        return fromTotalSupplyCap < maxSharesFromManager ? fromTotalSupplyCap : maxSharesFromManager;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address sharesOwner) public override(IERC4626, OrigamiErc4626) view returns (uint256 maxAssets) {
        uint256 fromTotalSupplyCap = _maxWithdraw(sharesOwner, withdrawalFeeBps());
        uint256 fromManager = _manager.maxWithdraw();
        return fromTotalSupplyCap < fromManager ? fromTotalSupplyCap : fromManager;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address sharesOwner) public override(IERC4626, OrigamiErc4626) view returns (uint256 maxShares) {
        uint256 fromTotalSupplyCap = _maxRedeem(sharesOwner);
        uint256 maxAssetsfromManager = _manager.maxWithdraw();
        if (maxAssetsfromManager == type(uint256).max) return fromTotalSupplyCap;

        (uint256 maxSharesFromManager,) = _previewWithdraw(
            maxAssetsfromManager,
            withdrawalFeeBps()
        );

        return fromTotalSupplyCap < maxSharesFromManager ? fromTotalSupplyCap : maxSharesFromManager;
    }
}
