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

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { OrigamiManagerPausable } from "contracts/investments/util/OrigamiManagerPausable.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Origami sUSDS++ Manager
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
    IOrigamiDelegated4626Vault public immutable vault;

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
    
    uint48 private _performanceFeeBpsForCaller;

    uint48 private _performanceFeeBpsForOrigami;

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
        uint48 performanceFeeBpsForCaller_,
        uint48 performanceFeeBpsForOrigami_
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

        // Max approval for deposits into sUSDS
        USDS.forceApprove(sUSDS_, type(uint256).max);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setPerformanceFees(uint48 callerFeeBps, uint48 origamiFeeBps) external override onlyElevatedAccess {
        uint48 newTotalFee = callerFeeBps + origamiFeeBps;

        // Only allowed to decrease the total fee or change allocation
        uint48 existingTotalFee = _performanceFeeBpsForCaller + _performanceFeeBpsForOrigami;
        if (newTotalFee > existingTotalFee) revert CommonEventsAndErrors.InvalidParam();
        
        emit PerformanceFeeSet(newTotalFee);
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
        nextFarmIndex = maxFarmIndex + 1;
        if (nextFarmIndex > MAX_FARMS) revert MaxFarms();

        // Use removeFarm to delete
        if (address(stakingAddress) == address(0)) revert InvalidFarm(nextFarmIndex);

        // Check this farm isn't already setup
        for (uint256 i; i < MAX_FARMS; ++i) {
            if (address(_farms[i].staking) == stakingAddress) revert FarmExistsAlready(stakingAddress);
        }

        ISkyStakingRewards staking = ISkyStakingRewards(stakingAddress);
        IERC20 rewardsToken = staking.rewardsToken();
        _farms[nextFarmIndex] = Farm(staking, rewardsToken, referralCode);

        // Max approve USDS for deposits
        USDS.forceApprove(address(staking), type(uint256).max);

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

        // Revoke approvals
        USDS.forceApprove(address(staking), 0);

        emit FarmRemoved(farmIndex, address(staking), address(farm.rewardsToken));
        delete _farms[farmIndex];
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function setFarmReferralCode(
        uint32 farmIndex,
        uint16 referralCode
    ) external override onlyElevatedAccess {
        Farm storage farm = _getFarm(farmIndex);
        emit FarmReferralCodeSet(farmIndex, referralCode);
        farm.referral = referralCode;
    }

    /// @inheritdoc IOrigamiDelegated4626VaultManager
    function deposit() external override returns (uint256 usdsDeposited) {
        // Note: Intentionally permisionless since donations are allowed anyway
        if (_paused.investmentsPaused) revert CommonEventsAndErrors.IsPaused();
        uint32 _currentFarmIndex = currentFarmIndex;

        // Deposit all at hand, including any donations.
        usdsDeposited = (_currentFarmIndex == 0)
            ? _depositIntoSavings()
            : _depositIntoFarm(_currentFarmIndex);
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
            : _withdrawFromFarm(_currentFarmIndex, usdsAmount, receiver);
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
        amountWithdrawn = (_currentFarmIndex == 0)
            ? _withdrawFromSavings(MAX_AMOUNT, address(this))
            : _withdrawFromFarm(_currentFarmIndex, MAX_AMOUNT, address(this));
        
        amountDeposited = (newFarmIndex == 0)
            ? _depositIntoSavings()
            : _depositIntoFarm(newFarmIndex);

        emit SwitchedFarms(_currentFarmIndex, newFarmIndex, amountWithdrawn, amountDeposited);
        currentFarmIndex = newFarmIndex;
        lastSwitchTime = uint32(block.timestamp);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function claimFarmRewards(uint32[] calldata farmIndexes) external override nonReentrant {
        HarvestRewardCache memory cache = HarvestRewardCache({
            swapper: swapper,
            caller: msg.sender,
            feeCollector: feeCollector,
            feeBpsForCaller: _performanceFeeBpsForCaller,
            feeBpsForOrigami: _performanceFeeBpsForOrigami
        });

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
    function performanceFeeBps() external view returns (uint48 /*forCaller*/, uint48 /*forOrigami*/) {
        return (_performanceFeeBpsForCaller, _performanceFeeBpsForOrigami);
    }

    /// @inheritdoc IOrigamiSuperSavingsUsdsManager
    function farmDetails(uint32 farmIndex) external override view returns (
        Farm memory farm,
        uint256 stakedBalance,
        uint256 totalSupply,
        uint256 rewardRate,
        uint256 unclaimedRewards
    ) {
        if (farmIndex == 0) {
            stakedBalance = sUSDS.balanceOf(address(this));
            totalSupply = sUSDS.totalSupply();
            rewardRate = sUSDS.ssr();
            // unclaimedRewards can remain as zero
        } else {
            farm = _getFarm(farmIndex);
            ISkyStakingRewards staking = farm.staking;
            stakedBalance = staking.balanceOf(address(this));
            totalSupply = staking.totalSupply();
            rewardRate = staking.rewardRate();
            unclaimedRewards = staking.earned(address(this));
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
        uint48 feeBpsForCaller;
        uint48 feeBpsForOrigami;
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

    function _depositIntoSavings() private returns (uint256 amountDeposited) {
        amountDeposited = USDS.balanceOf(address(this));
        if (amountDeposited > 0) {
            sUSDS.deposit(amountDeposited, address(this));
        }
    }
    
    function _depositIntoFarm(uint32 farmIndex) private returns (uint256 amountDeposited) {
        Farm storage farm = _getFarm(farmIndex);

        amountDeposited = USDS.balanceOf(address(this));
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
        uint32 farmIndex, 
        uint256 usdsAmount,
        address receiver
    ) private returns (uint256 amountWithdrawn) {
        Farm storage farm = _getFarm(farmIndex);
        ISkyStakingRewards staking = farm.staking;

        // dev note: ISkyStakingRewards does have an exit() function which exits the entire amount in one call
        // However it doesn't return the amount unstaked which we need anyway.
        amountWithdrawn = (usdsAmount == MAX_AMOUNT)
            ? staking.balanceOf(address(this))
            : usdsAmount;

        staking.withdraw(amountWithdrawn);
        if (receiver != address(this)) {
            USDS.safeTransfer(receiver, amountWithdrawn);
        }
    }

    modifier onlyVault() {
        if (msg.sender != address(vault)) revert CommonEventsAndErrors.InvalidAccess();
        _;
    }
}
