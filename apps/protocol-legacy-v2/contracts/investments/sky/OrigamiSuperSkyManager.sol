pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/sky/OrigamiSuperSkyManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISkyLockstakeEngine } from "contracts/interfaces/external/sky/ISkyLockstakeEngine.sol";
import { ISkyVat } from "contracts/interfaces/external/sky/ISkyVat.sol";

import { ISkyStakingRewards } from "contracts/interfaces/external/sky/ISkyStakingRewards.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiSuperSkyManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSkyManager.sol";
import { OrigamiDelegated4626Vault } from "contracts/investments/OrigamiDelegated4626Vault.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Origami Staked Sky Auto-compounder Manager
 * @notice Handles SKY deposits and switching between farms.
 * @dev Uses an immutable SKY Lockstake Engine. If that ever changes, a new vault will be deployed.
 * Users would need to withdraw from Origami Vault A and deposit into Origami Vault B.
 */
contract OrigamiSuperSkyManager is 
    IOrigamiSuperSkyManager,
    OrigamiElevatedAccess,
    OrigamiManagerPausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    IOrigamiDelegated4626Vault public immutable override vault;

    /// @inheritdoc IOrigamiSuperSkyManager
    IERC20 public immutable override SKY;

    /// @inheritdoc IOrigamiSuperSkyManager
    IERC20 public immutable override LSSKY;

    /// @inheritdoc IOrigamiSuperSkyManager
    ISkyLockstakeEngine public immutable override LOCKSTAKE_ENGINE;

    /// @inheritdoc IOrigamiSuperSkyManager
    address public immutable URN_ADDRESS;

    /// @inheritdoc IOrigamiSuperSkyManager
    address public override swapper;

    /// @inheritdoc IOrigamiSuperSkyManager
    uint32 public override maxFarmIndex;

    /// @inheritdoc IOrigamiSuperSkyManager
    uint32 public override currentFarmIndex;

    /// @inheritdoc IOrigamiSuperSkyManager
    uint32 public override switchFarmCooldown;

    /// @inheritdoc IOrigamiSuperSkyManager
    uint32 public override lastSwitchTime;

    /// @inheritdoc IOrigamiSuperSkyManager
    address public override feeCollector;
    
    uint16 private _performanceFeeBpsForCaller;

    uint16 private _performanceFeeBpsForOrigami;

    uint256 private immutable WAD = 1e18;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public override constant maxDeposit = type(uint256).max;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint256 public override constant maxWithdraw = type(uint256).max;

    /**
     * @dev The mapping of farm details.
     * `farmIndex` at index zero is empty, as that represents holding 
     * raw SKY in the urn (as LSSKY) rather than staking in a farm
     */
    mapping(uint256 farmIndex => Farm farm) private _farms;

    /// @dev Used to deposit/withdraw max possible.
    uint256 private constant MAX_AMOUNT = type(uint256).max;

    uint256 private constant MAX_FARMS = 100;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    uint16 public override constant depositFeeBps = 0;

    uint256 private constant URN_INDEX = 0;

    constructor(
        address initialOwner_,
        address vault_,
        address lockstakeEngine_,
        uint32 switchFarmCooldown_,
        address swapper_,
        address feeCollector_,
        uint16 performanceFeeBpsForCaller_,
        uint16 performanceFeeBpsForOrigami_
    ) 
        OrigamiElevatedAccess(initialOwner_)
    {
        vault = IOrigamiDelegated4626Vault(vault_);
        LOCKSTAKE_ENGINE = ISkyLockstakeEngine(lockstakeEngine_);
        SKY = IERC20(LOCKSTAKE_ENGINE.sky());
        LSSKY = IERC20(LOCKSTAKE_ENGINE.lssky());

        // Open a new urn - this contract will only ever hold one urn.
        URN_ADDRESS = LOCKSTAKE_ENGINE.open(URN_INDEX);

        switchFarmCooldown = switchFarmCooldown_;
        lastSwitchTime = uint32(block.timestamp);
        swapper = swapper_;

        feeCollector = feeCollector_;
        if (performanceFeeBpsForCaller_ + performanceFeeBpsForOrigami_ > OrigamiMath.BASIS_POINTS_DIVISOR) {
            revert CommonEventsAndErrors.InvalidParam();
        }
        _performanceFeeBpsForCaller = performanceFeeBpsForCaller_;
        _performanceFeeBpsForOrigami = performanceFeeBpsForOrigami_;

        // Max approval for deposits into the LockstakeEngine
        SKY.forceApprove(address(LOCKSTAKE_ENGINE), MAX_AMOUNT);
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function setPerformanceFees(uint16 callerFeeBps, uint16 origamiFeeBps) external override onlyElevatedAccess {
        uint16 newTotalFee = callerFeeBps + origamiFeeBps;

        // Only allowed to decrease the total fee or change allocation
        uint16 existingTotalFee = _performanceFeeBpsForCaller + _performanceFeeBpsForOrigami;
        if (newTotalFee > existingTotalFee) revert CommonEventsAndErrors.InvalidParam();

        // Ensure rewards are harvested on the existing farm prior to updating.
        _harvestFarm(currentFarmIndex);

        OrigamiDelegated4626Vault(address(vault)).logPerformanceFeesSet(newTotalFee);
        _performanceFeeBpsForCaller = callerFeeBps;
        _performanceFeeBpsForOrigami = origamiFeeBps;
    }
    
    /// @inheritdoc IOrigamiSuperSkyManager
    function setFeeCollector(address feeCollector_) external override onlyElevatedAccess {
        if (feeCollector_ == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(feeCollector_);
        feeCollector = feeCollector_;
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function setSwapper(address newSwapper) external override onlyElevatedAccess {
        if (newSwapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(newSwapper);

        emit SwapperSet(newSwapper);
        swapper = newSwapper;
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function setSwitchFarmCooldown(uint32 cooldown) external override onlyElevatedAccess {
        emit SwitchFarmCooldownSet(cooldown);
        switchFarmCooldown = cooldown;
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function addFarm(
        address stakingAddress, 
        uint16 referralCode
    ) external override onlyElevatedAccess returns (
        uint32 nextFarmIndex
    ) {
        // Farm index starts at 1
        nextFarmIndex = maxFarmIndex + 1; 
        if (nextFarmIndex > MAX_FARMS) revert MaxFarms();

        // Use removeFarm to delete
        if (address(stakingAddress) == address(0)) revert InvalidFarm(nextFarmIndex);

        // Check this farm isn't already setup
        for (uint256 i = 1; i < nextFarmIndex; ++i) {
            if (address(_farms[i].staking) == stakingAddress) revert FarmExistsAlready(stakingAddress);
        }

        ISkyStakingRewards staking = ISkyStakingRewards(stakingAddress);
        if (address(staking.stakingToken()) != address(LSSKY)) revert InvalidFarm(nextFarmIndex);

        IERC20 rewardsToken = staking.rewardsToken();
        _farms[nextFarmIndex] = Farm(staking, rewardsToken, referralCode);

        maxFarmIndex = nextFarmIndex;
        emit FarmAdded(nextFarmIndex, stakingAddress, address(rewardsToken), referralCode);
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function removeFarm(uint32 farmIndex) external override onlyElevatedAccess {
        if (farmIndex == currentFarmIndex) revert FarmStillInUse(farmIndex);
        if (farmIndex == 0) revert InvalidFarm(farmIndex);

        Farm storage farm = _getFarm(farmIndex);
        ISkyStakingRewards staking = farm.staking;

        // Ensure there aren't rewards to claim.
        if (staking.earned(URN_ADDRESS) > 0) {
            revert FarmStillInUse(farmIndex);
        }

        emit FarmRemoved(farmIndex, address(staking), address(farm.rewardsToken));
        delete _farms[farmIndex];
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function setFarmReferralCode(
        uint32 farmIndex,
        uint16 referralCode
    ) external override onlyElevatedAccess {
        Farm storage farm = _getFarm(farmIndex);
        farm.referral = referralCode;
        emit FarmReferralCodeSet(farmIndex, referralCode);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(uint256 assetsAmount) external override returns (uint256) {
        // Note: Intentionally permisionless since donations are allowed anyway -- either directly
        // into this contract, OR someone can lock in the LSE directly on this contract's behalf.

        _lock(assetsAmount);
        return assetsAmount;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(
        uint256 assetsAmount,
        address receiver
    ) external override onlyVault returns (uint256 assetsWithdrawn) {
        // `staking` has an exit() function which also claims rewards in the same tx.
        // However we intentionally want to separate that out to incentivise external claims.

        // The LOCKSTAKE_ENGINE may optionally take a fee on withdraw, by burning
        // a portion of the staked SKY.
        uint256 lseFee = LOCKSTAKE_ENGINE.fee();
        uint256 amountToFree;
        if (lseFee > 0) {
            // Back out the amount actually required to withdraw in order to end up receiving the 
            // requested `assetsAmount`.
            //
            // The vault calling this withdraw() is expected to take an exit fee from the caller,
            // on their vault shares first.
            amountToFree = assetsAmount.mulDiv(
                WAD,
                WAD - lseFee,
                // NB: LSE rounds the fee that it takes down, which is matched here.
                OrigamiMath.Rounding.ROUND_DOWN
            );
        } else {
            amountToFree = assetsAmount;
        }

        return LOCKSTAKE_ENGINE.free(address(this), URN_INDEX, receiver, amountToFree);
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function switchFarms(uint32 newFarmIndex) external override onlyElevatedAccess returns (
        uint256 amountWithdrawn,
        uint256 amountDeposited
    ) {
        if (block.timestamp < lastSwitchTime + switchFarmCooldown) revert BeforeCooldownEnd();

        uint32 _currentFarmIndex = currentFarmIndex;
        if (newFarmIndex == _currentFarmIndex) revert InvalidFarm(newFarmIndex);

        // Harvest rewards from current farm prior to switching
        _harvestFarm(_currentFarmIndex);

        Farm storage newFarm = _getFarm(newFarmIndex);
        LOCKSTAKE_ENGINE.selectFarm(
            address(this),
            URN_INDEX,
            address(newFarm.staking),
            newFarm.referral
        );
        
        amountWithdrawn = amountDeposited = stakedBalance();
        emit SwitchedFarms(_currentFarmIndex, newFarmIndex, amountWithdrawn, amountDeposited);
        currentFarmIndex = newFarmIndex;
        lastSwitchTime = uint32(block.timestamp);
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function claimFarmRewards(
        uint32[] calldata farmIndexes, 
        address incentivesReceiver
    ) external override nonReentrant {
        HarvestRewardCache memory cache = _populateRewardsCache(incentivesReceiver);
        uint32 farmIndex;
        uint256 _length = farmIndexes.length;
        for (uint256 i; i < _length; ++i) {
            farmIndex = farmIndexes[i];
            _harvestRewards(farmIndex, _farms[farmIndex], cache);
        }
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function reinvest() external {
        uint256 assets = unallocatedAssets();
        if (assets != 0) {
            _lock(assets);
            emit Reinvest(assets);
        }
    }

    /**
     * @notice Recover any token other than the underlying erc4626 asset.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (token == address(SKY)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external override view returns (address) {
        return address(SKY);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdrawalFeeBps() external view returns (uint16) {
        // represented in WAD [1e18]
        uint256 lseFee = LOCKSTAKE_ENGINE.fee();
        if (lseFee == 0) return 0;

        // Pass on Sky's unstake fee to exit, rounding up to the nearest basis point.
        // Safe to cast since the LSE fee needs to be less than 1e18
        return uint16(lseFee.scaleDown(1e14, OrigamiMath.Rounding.ROUND_UP));
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function performanceFeeBps() external view returns (uint16 /*forCaller*/, uint16 /*forOrigami*/) {
        return (_performanceFeeBpsForCaller, _performanceFeeBpsForOrigami);
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function farmDetails(uint32[] calldata farmIndexes) external override view returns (
        FarmDetails[] memory details
    ) {
        uint256 _length = farmIndexes.length;
        details = new FarmDetails[](_length);
        for (uint256 i; i < _length; ++i) {
            details[i] = _buildFarmDetails(farmIndexes[i]);
        }
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function totalAssets() external override view returns (uint256 totalManagedAssets) {
        // This contract may have a balance of SKY, from Cow Swapper rewards and/or donations
        // Intentionally does not consider earned but not yet claimed rewards (nor the claimed
        // rewards that have been sent to the swapper) since they are in different tokens 
        // which need swapping first.
        return unallocatedAssets() + stakedBalance();
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function stakedBalance() public override view returns (uint256) {
        ISkyVat vat = ISkyVat(LOCKSTAKE_ENGINE.vat());
        (uint256 ink,) = vat.urns(LOCKSTAKE_ENGINE.ilk(), URN_ADDRESS);
        return ink;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function unallocatedAssets() public override view returns (uint256) {
        return SKY.balanceOf(address(this));
    }

    /// @inheritdoc IOrigamiSuperSkyManager
    function getFarm(uint256 farmIndex) external override view returns (Farm memory farm) {
        return _farms[farmIndex];
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areDepositsPaused() external virtual override view returns (bool) {
        return _paused.investmentsPaused;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function areWithdrawalsPaused() external virtual override view returns (bool) {
        return _paused.exitsPaused;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public override pure returns (bool) {
        return interfaceId == type(IOrigamiSuperSkyManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function _getFarm(uint32 farmIndex) internal view returns (Farm storage farm) {
        farm = _farms[farmIndex];

        // Revert if it's inactive. farmIndex == 0 is valid.
        if (farmIndex > 0 && address(farm.staking) == address(0)) revert InvalidFarm(farmIndex);
    }

    struct HarvestRewardCache {
        address swapper;
        address caller;
        address feeCollector;
        uint16 feeBpsForCaller;
        uint16 feeBpsForOrigami;
    }

    function _transferRewards(
        IERC20 rewardsToken,
        uint256 totalRewardsClaimed,
        HarvestRewardCache memory cache
    ) internal returns (
        uint256 amountForCaller,
        uint256 amountForOrigami,
        uint256 amountForVault
    ) {
        amountForCaller = totalRewardsClaimed.mulDiv(
            cache.feeBpsForCaller, 
            OrigamiMath.BASIS_POINTS_DIVISOR, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        amountForOrigami = totalRewardsClaimed.mulDiv(
            cache.feeBpsForOrigami, 
            OrigamiMath.BASIS_POINTS_DIVISOR, 
            OrigamiMath.Rounding.ROUND_DOWN
        );

        uint256 totalFees = amountForCaller + amountForOrigami;
        if (cache.caller == cache.feeCollector) {
            _transfer(rewardsToken, totalFees, cache.caller);
        } else {
            _transfer(rewardsToken, amountForCaller, cache.caller);
            _transfer(rewardsToken, amountForOrigami, cache.feeCollector);
        }

        // The remainder is for the vault
        unchecked {
            amountForVault = totalRewardsClaimed - totalFees;
        }
        _transfer(rewardsToken, amountForVault, cache.swapper);
    }

    function _transfer(IERC20 rewardsToken, uint256 amount, address recipient) private {
        if (amount > 0) {
            rewardsToken.safeTransfer(recipient, amount);
        }
    }

    function _harvestRewards(
        uint32 farmIndex, 
        Farm storage farm, 
        HarvestRewardCache memory cache
    ) internal {
        // Nothing to harvest if the farm has been removed
        if (address(farm.staking) == address(0)) return;

        IERC20 rewardsToken = farm.rewardsToken;
        uint256 amountClaimed = LOCKSTAKE_ENGINE.getReward(
            address(this),
            URN_INDEX,
            address(farm.staking),
            address(this)
        );

        (
            uint256 amountForCaller,
            uint256 amountForOrigami,
            uint256 amountForVault
        ) = _transferRewards(rewardsToken, amountClaimed, cache);

        if (amountClaimed > 0) {
            emit ClaimedReward(
                farmIndex, 
                address(rewardsToken), 
                amountForCaller, 
                amountForOrigami, 
                amountForVault
            );
        }
    }

    function _buildFarmDetails(
        uint32 farmIndex
    ) private view returns (FarmDetails memory details) {
        // Only possible to deposit/withdraw from one farm at a time
        // via the lockstake engine. So only fill the staked balance if the
        // requested farmIndex is the current one.
        if (farmIndex == currentFarmIndex) {
            details.stakedBalance = stakedBalance();
        }

        // If this farm isn't valid or has been removed, where the staking address = 0,
        // then just don't populate the fields
        Farm memory farm = _farms[farmIndex];
        if (farmIndex == 0) {
            // The total supply of locked SKY across all users
            // All other details can remain zero/uninitialized
            details.totalSupply = LSSKY.totalSupply();
        } if (address(farm.staking) != address(0)) {
            details.farm = farm;
            details.totalSupply = farm.staking.totalSupply();
            details.rewardRate = farm.staking.rewardRate();
            details.unclaimedRewards = farm.staking.earned(URN_ADDRESS);
        }
    }

    function _populateRewardsCache(
        address incentivesReceiver
    ) private view returns (HarvestRewardCache memory) {
        return HarvestRewardCache({
            swapper: swapper,
            caller: incentivesReceiver,
            feeCollector: feeCollector,
            feeBpsForCaller: _performanceFeeBpsForCaller,
            feeBpsForOrigami: _performanceFeeBpsForOrigami
        });
    }
    
    function _lock(uint256 amount) private {
        LOCKSTAKE_ENGINE.lock(address(this), URN_INDEX, amount, _farms[currentFarmIndex].referral);
    }

    function _harvestFarm(uint32 farmIndex) private {
        if (farmIndex > 0) {
            // The `feeCollector` receives the extra incentives for harvesting.
            _harvestRewards(
                farmIndex, 
                _farms[farmIndex],
                _populateRewardsCache(feeCollector)
            );
        }
    }

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
