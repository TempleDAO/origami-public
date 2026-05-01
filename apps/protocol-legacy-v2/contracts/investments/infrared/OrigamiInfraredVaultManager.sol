pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/infrared/OrigamiInfraredVaultManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";
import { IOrigamiInfraredVaultManager } from "contracts/interfaces/investments/infrared/IOrigamiInfraredVaultManager.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IInfraredVault } from "contracts/interfaces/external/infrared/IInfraredVault.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiVestingReserves } from "contracts/investments/OrigamiVestingReserves.sol";

/**
 * @title Origami Infrared Vault Manager
 * @notice A manager for auto-compounding strategies on Infrared Vaults that handles staking of user
 * deposits and restaking of claimed rewards.
 */
contract OrigamiInfraredVaultManager is
    IOrigamiInfraredVaultManager,
    OrigamiVestingReserves,
    OrigamiElevatedAccess,
    OrigamiManagerPausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    IOrigamiDelegated4626Vault public immutable override vault;

    /// @dev The address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
    IERC20 internal immutable _asset;

    /// @inheritdoc IOrigamiInfraredVaultManager
    IInfraredVault public immutable override rewardVault;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public constant override depositFeeBps = 0;

    /// @inheritdoc IOrigamiInfraredVaultManager
    uint16 public constant override MAX_WITHDRAWAL_FEE_BPS = 330; // 3.3%

    /// @inheritdoc IOrigamiInfraredVaultManager
    uint16 public constant override MAX_PERFORMANCE_FEE_BPS = 100; // 1%

    /// @dev Used to deposit/withdraw max possible.
    uint256 private constant _MAX_AMOUNT = type(uint256).max;

    /// @inheritdoc IOrigamiCompoundingVaultManager
    address public override feeCollector;

    /// @inheritdoc IOrigamiCompoundingVaultManager
    address public override swapper;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public override withdrawalFeeBps;

    /// @dev Performance fees (in basis points) as a fraction of the _asset tokens reinvested.
    uint16 private _performanceFeeBps;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public constant override maxDeposit = type(uint256).max;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public constant override maxWithdraw = type(uint256).max;

    constructor(
        address initialOwner_,
        address vault_,
        address asset_,
        address rewardVault_,
        address feeCollector_,
        address swapper_,
        uint16 performanceFeeBps_
    )
        OrigamiElevatedAccess(initialOwner_)
        OrigamiVestingReserves(10 minutes)
    {
        vault = IOrigamiDelegated4626Vault(vault_);
        _asset = IERC20(asset_);
        rewardVault = IInfraredVault(rewardVault_);

        if (rewardVault.stakingToken() != asset_) revert CommonEventsAndErrors.InvalidToken(asset_);

        swapper = swapper_;
        feeCollector = feeCollector_;

        if (performanceFeeBps_ > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        _performanceFeeBps = performanceFeeBps_;

        // Max approval for deposits into the reward vault
        _asset.safeApprove(rewardVault_, _MAX_AMOUNT);
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function setSwapper(address _swapper) external override onlyElevatedAccess {
        if (_swapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit SwapperSet(_swapper);
        swapper = _swapper;
    }

    /// @inheritdoc IOrigamiInfraredVaultManager
    function setWithdrawalFee(uint16 withdrawalFeeBps_) external override onlyElevatedAccess {
        if (withdrawalFeeBps_ > MAX_WITHDRAWAL_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        emit FeeBpsSet(depositFeeBps, withdrawalFeeBps_);
        withdrawalFeeBps = uint16(withdrawalFeeBps_);
    }

    /// @inheritdoc IOrigamiInfraredVaultManager
    function setPerformanceFees(uint16 origamiFeeBps) external override onlyElevatedAccess {
        if (origamiFeeBps > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();

        // Ensure previous fees are collected before updating
        _harvestRewards();

        _performanceFeeBps = origamiFeeBps;
        OrigamiDelegated4626Vault(address(vault)).logPerformanceFeesSet(origamiFeeBps);
    }

    /**
     * @notice Recover tokens other than the underlying asset
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (token == address(_asset)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(uint256 assetsAmount) external override onlyVault returns (uint256) {
        if (assetsAmount > 0) {
            // Stake the user's deposit without taking any fees
            emit AssetStaked(assetsAmount);
            rewardVault.stake(assetsAmount);
        }

        // Harvest any claimable rewards, and compound any pending iBGT
        _harvestRewards();
        return assetsAmount;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(uint256 assetsAmount, address receiver) external override onlyVault returns (uint256) {
        // reinvest prior to withdrawing to take fees on pending asset balance and ensure the full amount denoted by
        // `totalAssets` is available
        _harvestRewards();

        if (assetsAmount > 0) {
            rewardVault.withdraw(assetsAmount);

            if (receiver != address(this)) {
                _asset.safeTransfer(receiver, assetsAmount);
            }

            emit AssetWithdrawn(assetsAmount);
        }

        return assetsAmount;
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function harvestRewards(address /* incentivesReceiver */) external override nonReentrant {
        // There are intentionally no incentives for the caller, as gas on bera is cheap
        _harvestRewards();
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    /// @dev Rewards must first be claimed from the reward vault (either by calling `harvestRewards`
    /// or by calling `getRewardForUser` on the underlying vault directly)
    /// Any balance of the asset token is restaked in the underlying vault after fees are taken.
    /// Any balance of other reward tokens is sent to the swapper to be sold for the asset token.
    function reinvest() external override nonReentrant {
        _reinvest();
    }

    /// @inheritdoc IOrigamiSwapCallback
    function swapCallback() external override nonReentrant {
        // Upon successful fills, the swapper will call this function to automatically reinvest the iBGT proceeds.
        _reinvest();
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function totalAssets() external view override returns (uint256 totalManagedAssets) {
        return _totalAssets(stakedAssets());
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function unallocatedAssets() external view override returns (uint256 amount) {
        // Balance of the asset in this contract are donations or rewards so a portion is reserved as fees for Origami
        amount = _asset.balanceOf(address(this));
        (amount,) = amount.splitSubtractBps(_performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @inheritdoc IOrigamiInfraredVaultManager
    function stakedAssets() public view override returns (uint256) {
        return rewardVault.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function getAllRewardTokens() public view override returns (address[] memory) {
        return rewardVault.getAllRewardTokens();
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areDepositsPaused() external view override returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areWithdrawalsPaused() external view override returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function performanceFeeBps() external view override returns (uint16 forCaller, uint16 forOrigami) {
        // Since gas is cheap on Berachain, no incentives for caller.
        // It would also complicate the architecture.
        return (0, _performanceFeeBps);
    }

    /// @inheritdoc IOrigamiInfraredVaultManager
    function unclaimedRewards() external view override returns (IInfraredVault.UserReward[] memory) {
        return rewardVault.getAllRewardsForUser(address(this));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IOrigamiDelegated4626VaultManager).interfaceId
            || interfaceId == type(IOrigamiCompoundingVaultManager).interfaceId
            || interfaceId == type(IOrigamiInfraredVaultManager).interfaceId;
    }

    /// @inheritdoc IOrigamiInfraredVaultManager
    function RESERVES_VESTING_DURATION() external view returns (uint48) {
        return reservesVestingDuration;
    }

    /// @dev Collect latest rewards from the vault and then call reinvest
    function _harvestRewards() private {
        rewardVault.getReward();
        _reinvest();
    }

    /// @dev Transfer non-asset rewards to the swapper, reinvest any asset tokens
    /// and checkpoint the new pending reserves
    function _reinvest() private {
        // Transfer all non-asset token rewards to the swapper
        _sendRewardsToSwapper();

        // Apply performance fees and reinvest (ie stake) the balance
        uint256 amountReinvested = _reinvestAssets();

        _checkpointPendingReserves(amountReinvested);
    }

    /// @dev Transfer all the non asset reward tokens to the swapper
    function _sendRewardsToSwapper() private {
        address[] memory rewardTokens = getAllRewardTokens();
        IERC20 rewardToken;
        uint256 rewardAmount;
        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardToken = IERC20(rewardTokens[i]);
            
            // Rewards in the base asset token are handled separately
            if (address(rewardToken) == address(_asset)) continue;

            rewardAmount = rewardToken.balanceOf(address(this));
            if (rewardAmount > 0) {
                rewardToken.safeTransfer(swapper, rewardAmount);
            }
        }
    }

    /// @dev Apply fees and reinvest the asset tokens
    function _reinvestAssets() private returns (uint256 amountForVault) {
        uint256 assetAmount = _asset.balanceOf(address(this));
        if (assetAmount > 0) {
            uint256 feeForOrigami;
            (amountForVault, feeForOrigami) = assetAmount.splitSubtractBps(
                _performanceFeeBps,
                OrigamiMath.Rounding.ROUND_DOWN
            );

            if (feeForOrigami > 0) {
                emit PerformanceFeesCollected(feeForOrigami);
                _asset.safeTransfer(feeCollector, feeForOrigami);
            }

            if (amountForVault > 0) {
                emit AssetStaked(amountForVault);
                rewardVault.stake(amountForVault);
            }
        }
    }

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
