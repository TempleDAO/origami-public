pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/erc4626/OrigamiErc4626WithRewardsManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IMerklDistributor } from "contracts/interfaces/external/merkl/IMerklDistributor.sol";
import { IMorphoUniversalRewardsDistributor } from "contracts/interfaces/external/morpho/IMorphoUniversalRewardsDistributor.sol";

import { IOrigamiCompoundingVaultManager } from "contracts/interfaces/investments/IOrigamiCompoundingVaultManager.sol";
import { IOrigamiErc4626WithRewardsManager } from "contracts/interfaces/investments/erc4626/IOrigamiErc4626WithRewardsManager.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiSwapCallback } from "contracts/interfaces/common/swappers/IOrigamiSwapCallback.sol";

import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiVestingReserves } from "contracts/investments/OrigamiVestingReserves.sol";

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
contract OrigamiErc4626WithRewardsManager is
    IOrigamiErc4626WithRewardsManager,
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

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    IERC4626 public immutable override underlyingVault;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public constant override depositFeeBps = 0;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public override withdrawalFeeBps;

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    uint16 public constant override MAX_WITHDRAWAL_FEE_BPS = 330; // 3.3%

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    uint16 public constant override MAX_PERFORMANCE_FEE_BPS = 1_000; // 10%

    /// @inheritdoc IOrigamiCompoundingVaultManager
    address public override swapper;

    /// @inheritdoc IOrigamiCompoundingVaultManager
    address public override feeCollector;

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    IMerklDistributor public override merklRewardsDistributor;

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    IMorphoUniversalRewardsDistributor public override morphoRewardsDistributor;

    /// @dev The expected reward tokens
    address[] private _rewardTokens;

    /// @dev Performance fees (in basis points) for Origami as a fraction of the asset tokens reinvested.
    /// If `underlyingVault` shares are donated into the vault (or as merkl/morpho rewards) it will hit 
    /// the totalAssets immediately (not vested over time) and fees aren't taken on that amount.
    uint16 private _performanceFeeBps;

    constructor(
        address initialOwner_,
        address vault_,
        address underlyingVault_,
        address feeCollector_,
        address swapper_,
        uint16 performanceFeeBps_,
        uint48 reservesVestingDuration_,
        address merklRewardsDistributor_,   
        address morphoRewardsDistributor_
    )
        OrigamiElevatedAccess(initialOwner_)
        OrigamiVestingReserves(reservesVestingDuration_)
    {
        vault = IOrigamiDelegated4626Vault(vault_);
        underlyingVault = IERC4626(underlyingVault_);
        _asset = IERC20(underlyingVault.asset());        

        swapper = swapper_;
        feeCollector = feeCollector_;
        if (performanceFeeBps_ > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        _performanceFeeBps = performanceFeeBps_;

        // Allowed to be the zero address, meaning it's not enabled.
        merklRewardsDistributor = IMerklDistributor(merklRewardsDistributor_);
        morphoRewardsDistributor = IMorphoUniversalRewardsDistributor(morphoRewardsDistributor_);

        // Max approval for deposits into the underyling vault
        _asset.safeApprove(underlyingVault_, type(uint256).max);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setReservesVestingDuration(uint48 durationInSeconds) external override onlyElevatedAccess {
        _setReservesVestingDuration(durationInSeconds);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setRewardTokens(address[] calldata newRewardTokens) external override onlyElevatedAccess {
        // Elevated access trusted to check for duplicates/etc. Also allowed to be empty.
        _rewardTokens = newRewardTokens;
        emit RewardTokensSet();
    }
    
    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setMerklRewardsDistributor(address distributor) external override onlyElevatedAccess  {
        // OK to be set to address(0), effectively disabling
        merklRewardsDistributor = IMerklDistributor(distributor);
        emit MerklRewardsDistributorSet(distributor);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setMorphoRewardsDistributor(address distributor) external override onlyElevatedAccess  {
        // OK to be set to address(0), effectively disabling
        morphoRewardsDistributor = IMorphoUniversalRewardsDistributor(distributor);
        emit MorphoRewardsDistributorSet(distributor);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function merklToggleOperator(address operator) external override onlyElevatedAccess {
        // A log event is emitted by the merkl distributor
        merklRewardsDistributor.toggleOperator(address(this), operator);
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

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setWithdrawalFee(uint16 withdrawalFeeBps_) external override onlyElevatedAccess {
        if (withdrawalFeeBps_ > MAX_WITHDRAWAL_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        emit FeeBpsSet(depositFeeBps, withdrawalFeeBps_);
        withdrawalFeeBps = uint16(withdrawalFeeBps_);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function setPerformanceFees(uint16 origamiFeeBps) external override onlyElevatedAccess {
        if (origamiFeeBps > MAX_PERFORMANCE_FEE_BPS) revert CommonEventsAndErrors.InvalidParam();
        
        // Ensure previous fees are collected before updating
        _reinvest();

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
        if (_isProtectedToken(token)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(uint256 assetsAmount) external override onlyVault returns (uint256) {
        if (assetsAmount > 0) {
            // Deposit in the underlying vault without taking fees
            emit AssetStaked(assetsAmount);
            underlyingVault.deposit(assetsAmount, address(this));
        }

        return assetsAmount;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(uint256 assetsAmount, address receiver) external override onlyVault returns (uint256) {
        if (assetsAmount > 0) {
            emit AssetWithdrawn(assetsAmount);
            underlyingVault.withdraw(assetsAmount, receiver, address(this));
        }

        return assetsAmount;
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function merklClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external override {
        // reinvest() may need to be called externally to ensure rewards are sent
        // to the swapper. This can be monitored/actioned by a keeper

        // Create a users list for this address matching the length of tokens/amounts/proofs 
        // No need to explicitly check tokens/amounts/proofs lengths are the same 
        address[] memory users = new address[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            users[i] = address(this);
        }
        
        // Claim from merkl. No check required on the tokens here
        merklRewardsDistributor.claim(users, tokens, amounts, proofs);

        // Sweep any reward tokens claimed into this contract to the swapper
        _reinvest();
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function morphoClaim(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external override {
        // Note anyone is allowed to claim on behalf of this contract, in which case
        // reinvest() may need to be called externally to ensure rewards are sent
        // to the swapper. This can be monitored/actioned by a keeper
        for (uint256 i; i < tokens.length; ++i) {
            morphoRewardsDistributor.claim(address(this), tokens[i], amounts[i], proofs[i]);
        }

        // Sweep any reward tokens claimed into this contract to the swapper
        _reinvest();
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function harvestRewards(address /*incentivesReceiver*/) external override nonReentrant {
        // This only does the reinvest, as Merkl/Morpho reward claims require more complex
        // interactions with extra parameters. Implemented to as it's required in the interface
        _reinvest();
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function reinvest() external override nonReentrant {
        _reinvest();
    }

    /// @inheritdoc IOrigamiSwapCallback
    function swapCallback() external override nonReentrant {
        // If the swapper is of type `OrigamiSwapperWithCallback`, upon successful fills, 
        // it will call this function to automatically reinvest the proceeds.
        _reinvest();
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function maxDeposit() external override view returns (uint256) {
        return underlyingVault.maxDeposit(address(this));
    }
    
    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function maxWithdraw() external override view returns (uint256) {
        return underlyingVault.maxWithdraw(address(this));
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function totalAssets() external view override returns (uint256 totalManagedAssets) {
        return _totalAssets(depositedAssets());
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external view override returns (address) {
        return address(_asset);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function unallocatedAssets() public view override returns (uint256 amount) {
        // Balance of the asset in this contract are donations or rewards. A portion of these are reserved
        // for fees
        amount = _asset.balanceOf(address(this));
        (amount,) = amount.splitSubtractBps(_performanceFeeBps, OrigamiMath.Rounding.ROUND_DOWN);
    }

    /// @inheritdoc IOrigamiErc4626WithRewardsManager
    function depositedAssets() public view override returns (uint256) {
        // Intentionally does not consider earned but not yet claimed rewards (nor the claimed
        // rewards that have been sent to the swapper) since they are in different tokens 
        // which need swapping first.
        // Also doesn't include `unallocatedAssets()`, as they will be vested in over time when reinvest() is called
        return underlyingVault.previewRedeem(
            underlyingVault.balanceOf(address(this))
        );
    }

    /// @inheritdoc IOrigamiCompoundingVaultManager
    function getAllRewardTokens() public view override returns (address[] memory) {
        return _rewardTokens;
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
        return (0, _performanceFeeBps);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IOrigamiDelegated4626VaultManager).interfaceId
            || interfaceId == type(IOrigamiCompoundingVaultManager).interfaceId
            || interfaceId == type(IOrigamiErc4626WithRewardsManager).interfaceId;
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

    /// @dev Cannot rescue (or send to the swapper) this vault's asset or the underlying vault ERC4626 token
    function _isProtectedToken(address token) private view returns (bool) {
        return token == address(_asset) || token == address(underlyingVault);
    }

    /// @dev Transfer all the non asset reward tokens to the swapper
    function _sendRewardsToSwapper() private {
        uint256 length = _rewardTokens.length;
        IERC20 rewardToken;
        uint256 rewardAmount;
        for (uint256 i; i < length; ++i) {
            rewardToken = IERC20(_rewardTokens[i]);
            
            // Rewards in the base asset token or underlying vault are handled separately
            if (_isProtectedToken(address(rewardToken))) continue;

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
                _asset.safeTransfer(feeCollector, feeForOrigami);
            }

            if (amountForVault > 0) {
                emit AssetStaked(amountForVault);
                underlyingVault.deposit(amountForVault, address(this));
            }

            emit ClaimedReward(address(vault), 0, feeForOrigami, amountForVault);
        }
    }

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
