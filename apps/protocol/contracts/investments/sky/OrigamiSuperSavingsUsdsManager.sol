pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/sky/OrigamiSuperSavingsUsdsManager.sol)

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISkySUsds } from "contracts/interfaces/external/sky/ISkySUsds.sol";

import { ISkyStakingRewards } from "contracts/interfaces/external/sky/ISkyStakingRewards.sol";
import { IOrigamiDelegated4626Vault } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626Vault.sol";
import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { IOrigamiSuperSavingsUsdsManager } from "contracts/interfaces/investments/sky/IOrigamiSuperSavingsUsdsManager.sol";
import { OrigamiSuperSavingsUsdsVault } from "contracts/investments/sky/OrigamiSuperSavingsUsdsVault.sol";

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Origami sUSDS+s Manager
 * @notice Handles USDS deposits and switching between farms
 */
contract OrigamiSuperSavingsUsdsManager is 
    IOrigamiSuperSavingsUsdsManager,
    OrigamiElevatedAccess,
    OrigamiManagerPausable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    IOrigamiDelegated4626Vault public immutable override vault;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    IERC20 public immutable override USDS;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    ISkySUsds public immutable override sUSDS;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    address public override swapper;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    uint32 public override maxFarmIndex;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    uint32 public override currentFarmIndex;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    uint32 public override switchFarmCooldown;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    uint32 public override lastSwitchTime;

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    address public override feeCollector;
    
    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    uint16 public sUsdsReferral;

    uint16 private _performanceFeeBpsForCaller;

    uint16 private _performanceFeeBpsForOrigami;

    /**
     * @dev The mapping of farm details.
     * `farmIndex` at index zero is empty, as that represents deposits into `sUSDS`
     */
    mapping(uint256 farmIndex => Farm farm) private _farms;

    /// @dev Used to deposit/withdraw max possible.
    uint256 private constant MAX_AMOUNT = type(uint256).max;

    uint256 private constant MAX_FARMS = 100;

    constructor(
        address initialOwner_,
        address vault_,
        address sUSDS_,
        uint32 switchFarmCooldown_,
        address swapper_,
        address feeCollector_,
        uint16 performanceFeeBpsForCaller_,
        uint16 performanceFeeBpsForOrigami_
    ) 
        OrigamiElevatedAccess(initialOwner_)
    {
        vault = IOrigamiDelegated4626Vault(vault_);
        USDS = IERC20(vault.asset());
        sUSDS = ISkySUsds(sUSDS_);
        switchFarmCooldown = switchFarmCooldown_;
        lastSwitchTime = uint32(block.timestamp);
        swapper = swapper_;

        feeCollector = feeCollector_;
        if (performanceFeeBpsForCaller_ + performanceFeeBpsForOrigami_ > OrigamiMath.BASIS_POINTS_DIVISOR) {
            revert CommonEventsAndErrors.InvalidParam();
        }
        _performanceFeeBpsForCaller = performanceFeeBpsForCaller_;
        _performanceFeeBpsForOrigami = performanceFeeBpsForOrigami_;

        // Max approval for deposits into sUSDS as the starting farm
        USDS.forceApprove(sUSDS_, MAX_AMOUNT);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setPerformanceFees(uint16 callerFeeBps, uint16 origamiFeeBps) external override onlyElevatedAccess {
        uint16 newTotalFee = callerFeeBps + origamiFeeBps;

        // Only allowed to decrease the total fee or change allocation
        uint16 existingTotalFee = _performanceFeeBpsForCaller + _performanceFeeBpsForOrigami;
        if (newTotalFee > existingTotalFee) revert CommonEventsAndErrors.InvalidParam();

        // Ensure rewards are harvested on the existing farm prior to updating.
        uint32 _currentFarmIndex = currentFarmIndex;
        if(_currentFarmIndex > 0) {
            // The `feeCollector` receives the extra incentives for harvesting.
            _harvestRewards(
                _currentFarmIndex, 
                _farms[_currentFarmIndex],
                _populateRewardsCache(feeCollector)
            );
        }

        OrigamiSuperSavingsUsdsVault(address(vault)).logPerformanceFeesSet(newTotalFee);
        _performanceFeeBpsForCaller = callerFeeBps;
        _performanceFeeBpsForOrigami = origamiFeeBps;
    }
    
    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setFeeCollector(address _feeCollector) external override onlyElevatedAccess {
        if (_feeCollector == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        emit FeeCollectorSet(_feeCollector);
        feeCollector = _feeCollector;
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setSwapper(address newSwapper) external override onlyElevatedAccess {
        if (newSwapper == address(0)) revert CommonEventsAndErrors.InvalidAddress(newSwapper);

        emit SwapperSet(newSwapper);
        swapper = newSwapper;
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setSwitchFarmCooldown(uint32 cooldown) external override onlyElevatedAccess {
        emit SwitchFarmCooldownSet(cooldown);
        switchFarmCooldown = cooldown;
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function addFarm(
        address stakingAddress, 
        uint16 referralCode
    ) external override onlyElevatedAccess returns (
        uint32 nextFarmIndex
    ) {
        // Farm index starts at 1
        uint32 _maxFarmIndex = maxFarmIndex;
        nextFarmIndex = _maxFarmIndex + 1;
        if (nextFarmIndex > MAX_FARMS) revert MaxFarms();

        // Use removeFarm to delete
        if (address(stakingAddress) == address(0)) revert InvalidFarm(nextFarmIndex);

        // Check this farm isn't already setup
        for (uint256 i = 1; i <= _maxFarmIndex; ++i) {
            if (address(_farms[i].staking) == stakingAddress) revert FarmExistsAlready(stakingAddress);
        }

        ISkyStakingRewards staking = ISkyStakingRewards(stakingAddress);
        if (address(staking.stakingToken()) != address(USDS)) revert InvalidFarm(nextFarmIndex);

        IERC20 rewardsToken = staking.rewardsToken();
        _farms[nextFarmIndex] = Farm(staking, rewardsToken, referralCode);

        maxFarmIndex = nextFarmIndex;
        emit FarmAdded(nextFarmIndex, stakingAddress, address(rewardsToken), referralCode);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function removeFarm(uint32 farmIndex) external override onlyElevatedAccess {
        if (farmIndex == currentFarmIndex) revert FarmStillInUse(farmIndex);

        // Ensure there isn't still a balance staked, or rewards to claim.
        Farm storage farm = _getFarm(farmIndex);
        ISkyStakingRewards staking = farm.staking;
        if (staking.balanceOf(address(this)) > 0 || staking.earned(address(this)) > 0) {
            revert FarmStillInUse(farmIndex);
        }

        emit FarmRemoved(farmIndex, address(staking), address(farm.rewardsToken));
        delete _farms[farmIndex];
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setFarmReferralCode(
        uint32 farmIndex,
        uint16 referralCode
    ) external override onlyElevatedAccess {
        if (farmIndex == 0) {
            sUsdsReferral = referralCode;
        } else {
            Farm storage farm = _getFarm(farmIndex);
            farm.referral = referralCode;
        }

        emit FarmReferralCodeSet(farmIndex, referralCode);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit(uint256 assetsAmount) external override returns (uint256 assetsDeposited) {
        // Note: Intentionally permisionless since donations are allowed anyway
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        uint32 _currentFarmIndex = currentFarmIndex;

        // Deposit all at hand, including any donations.
        assetsDeposited = (_currentFarmIndex == 0)
            ? _depositIntoSavings(assetsAmount)
            : _depositIntoFarm(_farms[_currentFarmIndex], assetsAmount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function withdraw(
        uint256 usdsAmount,
        address receiver
    ) external override onlyVault returns (uint256 usdsWithdrawn) {
        if (_paused.exitsPaused) revert CommonEventsAndErrors.IsPaused();

        uint32 _currentFarmIndex = currentFarmIndex;

        usdsWithdrawn = (_currentFarmIndex == 0)
            ? _withdrawFromSavings(usdsAmount, receiver)
            : _withdrawFromFarm(
                _farms[_currentFarmIndex].staking,
                usdsAmount,
                receiver
            );
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function switchFarms(uint32 newFarmIndex) external override onlyElevatedAccess returns (
        uint256 amountWithdrawn,
        uint256 amountDeposited
    ) {
        if (block.timestamp < lastSwitchTime + switchFarmCooldown) revert BeforeCooldownEnd();

        uint32 _currentFarmIndex = currentFarmIndex;
        if (newFarmIndex == _currentFarmIndex) revert InvalidFarm(newFarmIndex);

        // The amounts withdrawn and then deposited may differ, due to donations, which is ok.
        if (_currentFarmIndex == 0) {
            amountWithdrawn = _withdrawFromSavings(MAX_AMOUNT, address(this));
            USDS.forceApprove(address(sUSDS), 0);
        } else {
            ISkyStakingRewards staking = _farms[_currentFarmIndex].staking;
            amountWithdrawn = _withdrawFromFarm(
                staking, 
                MAX_AMOUNT, 
                address(this)
            );
            USDS.forceApprove(address(staking), 0);
        }
        
        if (newFarmIndex == 0) {
            USDS.forceApprove(address(sUSDS), MAX_AMOUNT);
            amountDeposited = _depositIntoSavings(MAX_AMOUNT);
        } else {
            // Ensure we check that the newFarmIndex is valid
            Farm storage farm = _getFarm(newFarmIndex);
            USDS.forceApprove(address(farm.staking), MAX_AMOUNT);
            amountDeposited = _depositIntoFarm(farm, MAX_AMOUNT);
        }

        emit SwitchedFarms(_currentFarmIndex, newFarmIndex, amountWithdrawn, amountDeposited);
        currentFarmIndex = newFarmIndex;
        lastSwitchTime = uint32(block.timestamp);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function claimFarmRewards(
        uint32[] calldata farmIndexes, 
        address incentivesReceiver
    ) external override nonReentrant {
        HarvestRewardCache memory cache = _populateRewardsCache(incentivesReceiver);
        uint32 farmIndex;
        uint256 _length = farmIndexes.length;
        for (uint256 i; i < _length; ++i) {
            farmIndex = farmIndexes[i];
            _harvestRewards(farmIndex, _getFarm(farmIndex), cache);
        }
    }

    /**
     * @notice Recover any token other than the underlying erc4626 asset.
     * @param token Token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(address token, address to, uint256 amount) external onlyElevatedAccess {
        if (token == address(USDS) || token == address(sUSDS)) revert CommonEventsAndErrors.InvalidToken(token);

        emit CommonEventsAndErrors.TokenRecovered(to, token, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function asset() external override view returns (address) {
        return address(USDS);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function performanceFeeBps() external view returns (uint16 /*forCaller*/, uint16 /*forOrigami*/) {
        return (_performanceFeeBpsForCaller, _performanceFeeBpsForOrigami);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function farmDetails(uint32[] calldata farmIndexes) external override view returns (
        FarmDetails[] memory details
    ) {
        uint256 _length = farmIndexes.length;
        details = new FarmDetails[](_length);
        uint32 farmIndex;
        for (uint256 i; i < _length; ++i) {
            farmIndex = farmIndexes[i];
            details[i] = farmIndex == 0
                ? _buildSUsdsDetails()
                : _buildFarmDetails(farmIndex);
        }
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function totalAssets() external override view returns (uint256 totalManagedAssets) {
        // This contract may have a balance of USDS, from Cow Swapper rewards and/or donations
        // And also included sUSDS deposits (also may be donations)
        totalManagedAssets = (
            USDS.balanceOf(address(this)) +
            sUSDS.maxWithdraw(address(this))
        );

        // Intentionally does not consider earned but not yet claimed rewards
        // since they are in different tokens which need swapping first.
        uint32 _currentFarmIndex = currentFarmIndex;
        if (_currentFarmIndex > 0) {
            totalManagedAssets += _farms[_currentFarmIndex].staking.balanceOf(address(this));
        }
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
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
        return interfaceId == type(IOrigamiSuperSavingsUsdsManager).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function _getFarm(uint32 farmIndex) internal view returns (Farm storage farm) {
        farm = _farms[farmIndex];
        if (address(farm.staking) == address(0)) revert InvalidFarm(farmIndex);
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
        if (amountForCaller > 0) {
            rewardsToken.safeTransfer(cache.caller, amountForCaller);
        }

        amountForOrigami = totalRewardsClaimed.mulDiv(
            cache.feeBpsForOrigami, 
            OrigamiMath.BASIS_POINTS_DIVISOR, 
            OrigamiMath.Rounding.ROUND_DOWN
        );
        if (amountForOrigami > 0) {
            rewardsToken.safeTransfer(cache.feeCollector, amountForOrigami);
        }

        // The remainder is for the vault        
        unchecked {
            amountForVault = totalRewardsClaimed - amountForCaller - amountForOrigami;
        }
        if (amountForVault > 0) {
            rewardsToken.safeTransfer(cache.swapper, amountForVault);
        }
    }

    function _harvestRewards(
        uint32 farmIndex, 
        Farm storage farm, 
        HarvestRewardCache memory cache
    ) internal {
        IERC20 rewardsToken = farm.rewardsToken;
        farm.staking.getReward();
        uint256 amountClaimed = rewardsToken.balanceOf(address(this));

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

    function _depositIntoSavings(uint256 assetsAmount) private returns (uint256 amountDeposited) {
        amountDeposited = assetsAmount == MAX_AMOUNT 
            ? USDS.balanceOf(address(this))
            : assetsAmount;

        if (amountDeposited > 0) {
            uint16 referral = sUsdsReferral;
            if (referral == 0) {
                sUSDS.deposit(amountDeposited, address(this));
            } else {
                sUSDS.deposit(amountDeposited, address(this), referral);
            }
        }
    }
    
    function _depositIntoFarm(Farm storage farm, uint256 assetsAmount) private returns (uint256 amountDeposited) {
        amountDeposited = assetsAmount == MAX_AMOUNT
            ? USDS.balanceOf(address(this))
            : assetsAmount;
            
        if (amountDeposited > 0) {
            uint16 referral = farm.referral;
            if (referral == 0) {
                farm.staking.stake(amountDeposited);
            } else {
                farm.staking.stake(amountDeposited, referral);
            }
        }
    }

    function _withdrawFromSavings(uint256 usdsAmount, address receiver) private returns (uint256 amountWithdrawn) {
        // Use shares for max amount, otherwise assets.
        if (usdsAmount == MAX_AMOUNT) {
            amountWithdrawn = sUSDS.redeem(sUSDS.balanceOf(address(this)), receiver, address(this));
        } else {
            amountWithdrawn = usdsAmount;
            sUSDS.withdraw(usdsAmount, receiver, address(this));
        }
    }
    
    function _withdrawFromFarm(
        ISkyStakingRewards staking,
        uint256 usdsAmount,
        address receiver
    ) private returns (uint256 amountWithdrawn) {
        // `staking` has an exit() function which also claims rewards in the same tx.
        // However we intentionally want to separate that out to incentivise external claims.
        amountWithdrawn = (usdsAmount == MAX_AMOUNT)
            ? staking.balanceOf(address(this))
            : usdsAmount;

        staking.withdraw(amountWithdrawn);
        if (receiver != address(this)) {
            USDS.safeTransfer(receiver, amountWithdrawn);
        }
    }

    function _buildSUsdsDetails() private view returns (FarmDetails memory details) {
        // The current amount of USDS which can be redeemed
        // excluding any any limits that maxWithdraw may have
        details.stakedBalance = sUSDS.previewRedeem(
            sUSDS.balanceOf(address(this))
        );

        // The total amount of USDS within sUSDS
        details.totalSupply = sUSDS.totalAssets();

        // The current sUSDS savings rate
        details.rewardRate = sUSDS.ssr();

        // unclaimedRewards, farmIndex can remain as zero
        // farmConfig can remain uninitialized
    }

    function _buildFarmDetails(
        uint32 farmIndex
    ) private view returns (FarmDetails memory details) {
        // If this farm isn't valid or has been removed, then 
        // just don't populate the fields
        Farm memory farm = _farms[farmIndex];
        if (address(farm.staking) != address(0)) {
            details.farm = farm;
            details.stakedBalance = farm.staking.balanceOf(address(this));
            details.totalSupply = farm.staking.totalSupply();
            details.rewardRate = farm.staking.rewardRate();
            details.unclaimedRewards = farm.staking.earned(address(this));
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
    
    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
