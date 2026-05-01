pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/sky/IOrigamiSuperSkyManager.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISkyLockstakeEngine } from "contracts/interfaces/external/sky/ISkyLockstakeEngine.sol";

import { IOrigamiDelegated4626VaultManager } from "contracts/interfaces/investments/erc4626/IOrigamiDelegated4626VaultManager.sol";
import { ISkyStakingRewards } from "contracts/interfaces/external/sky/ISkyStakingRewards.sol";

/**
 * @title Origami Staked Sky Auto-compounder Manager
 * @notice Handles SKY deposits and switching between farms.
 * @dev Uses an immutable SKY Lockstake Engine. If that ever changes, a new vault will be deployed.
 * Users would need to withdraw from Origami Vault A and deposit into Origami Vault B.
 */
interface IOrigamiSuperSkyManager is IOrigamiDelegated4626VaultManager {
    error InvalidFarm(uint32 farmIndex);
    error FarmStillInUse(uint32 farmIndex);
    error BeforeCooldownEnd();
    error MaxFarms();
    error FarmExistsAlready(address stakingAddress);

    event FarmReferralCodeSet(uint32 indexed farmIndex, uint16 referralCode);

    event SwitchFarmCooldownSet(uint32 cooldown);

    event SwapperSet(address indexed newSwapper);

    event FarmAdded(
        uint32 indexed farmIndex,
        address indexed stakingAddress,
        address indexed rewardsToken,
        uint16 referralCode
    );

    event FarmRemoved(
        uint32 indexed farmIndex,
        address indexed stakingAddress,
        address indexed rewardsToken
    );

    event SwitchedFarms(
        uint32 indexed oldFarmIndex, 
        uint32 indexed newFarmIndex, 
        uint256 amountWithdrawn, 
        uint256 amountDeposited
    );

    event ClaimedReward(
        uint32 indexed farmIndex, 
        address indexed rewardsToken, 
        uint256 amountForCaller, 
        uint256 amountForOrigami, 
        uint256 amountForVault
    );

    event Reinvest(uint256 amount);

    /// @dev Configuration required for a SKY farm
    struct Farm {
        /// @dev The address of the Synthetix-like SKY staking contract
        ISkyStakingRewards staking;

        /// @dev The rewards token for this given staking contract
        IERC20 rewardsToken;

        /// @dev The referral code representing Origami
        uint16 referral;
    }

    /**
     * @notice Set the performance fees for the caller and origami
     * @dev Total fees cannot increase, but the ratio can be changed.
     * Fees are distributed when claimFarmRewards() is called
     */
    function setPerformanceFees(uint16 callerFeeBps, uint16 origamiFeeBps) external;

    /**
     * @notice Set the address used to collect the Origami performance fees.
     */
    function setFeeCollector(address _feeCollector) external;

    /**
     * @notice Set the swapper contract responsible for swapping 
     * farm reward tokens into SKY
     */
    function setSwapper(address swapper) external;

    /**
     * @notice Set the cooldown for how frequently this contract is allowed to switch between
     * farms. Used to avoid thrashing.
     */
    function setSwitchFarmCooldown(uint32 cooldown) external;

    /**
     * @notice Add a new SKY farm configuration 
     * @dev Only a maximum of 100 farms can be added. Will revert if the same `stakingAddress` is 
     * added a second time.
     */ 
    function addFarm(
        address stakingAddress, 
        uint16 referralCode
    ) external returns (
        uint32 newFarmIndex
    );

    /**
     * @notice Remove a deprecated farm configuration item for house keeping
     * @dev This will revert if there's still a staked balance or rewards to claim.
     * If a farm is removed, the `maxFarmIndex` doesn't decrease
     */ 
    function removeFarm(uint32 farmIndex) external;

    /**
     * @notice Set the referral code for a given SKY staking contract
     */
    function setFarmReferralCode(
        uint32 farmIndex,
        uint16 referralCode
    ) external;

    /**
     * @notice Elevated access can decide to switch which farm to use if the yield is greater
     */
    function switchFarms(uint32 newFarmIndex) external returns (
        uint256 amountWithdrawn,
        uint256 amountDeposited
    );

    /**
     * @notice A permissionless function to claim farm rewards from a given farm
     * - The caller can nominate an address to receive a portion of these rewards (to compensate for gas)
     * - Origami will earn a portion of these rewards (as performance fee)
     * - The remainder is sent to a swapper contract to swap for SKY.
     * SKY proceeds from the swap will sent back to this contract, ready to add to the
     * current farm on the next deposit.
     */
    function claimFarmRewards(
        uint32[] calldata farmIndexes,
        address incentivesReceiver
    ) external;

    /**
     * @notice Reinvest any unallocated assets into the currently active farm
     */
    function reinvest() external;

    /**
     * @notice The Sky contract
     */
    function SKY() external view returns (IERC20);

    /**
     * @notice The Locked SKY contract, which is staked into farms
     * @dev rate: 1 SKY === 1 LSSKY
     */
    function LSSKY() external view returns (IERC20);

    /**
     * @notice The Sky Lockstake Engine contract
     */
    function LOCKSTAKE_ENGINE() external view returns (ISkyLockstakeEngine);

    /**
     * @notice The address of this contract's urn in the Sky lockstake engine
     */
    function URN_ADDRESS() external view returns (address);

    /**
     * @notice The performance fee to the caller (to compensate for gas) and Origami treasury
     * Represented in basis points
     */
    function performanceFeeBps() external view returns (uint16 forCaller, uint16 forOrigami);

    /**
     * @notice The address used to collect the Origami performance fees.
     */
    function feeCollector() external view returns (address);

    /**
     * @notice The swapper contract responsible for swapping 
     * farm reward tokens into SKY
     */
    function swapper() external view returns (address);

    /**
     * @notice The cooldown for how frequently this contract is allowed to switch between
     * farms. Used to avoid thrashing.
     */
    function switchFarmCooldown() external view returns (uint32);

    /**
     * @notice The last time that the farm was switched
     */
    function lastSwitchTime() external view returns (uint32);

    /**
     * @notice The number of Sky farms, not including holding raw
     * SKY in the urn rather than farming
     */
    function maxFarmIndex() external view returns (uint32);

    /**
     * @notice The currently selected farm for deposits.
     * @dev
     * - index 0: Raw SKY is held in the assigned Lockstake Engine urn
     * - index 1+: A SKY is staked in a farm
     */
    function currentFarmIndex() external view returns (uint32);
    
    /**
     * @notice The farm config of a particular index
     * @dev Does not revert - A farm index is invalid if the farmIndex is > 0 and
     * `farm.staking` is address(0)
     */
    function getFarm(uint256 farmIndex) external view returns (Farm memory farm);

    struct FarmDetails {
        /// @dev The farm configuration
        Farm farm;

        /// @dev The amount of SKY staked in the farm
        /// If no farm is chosen, this will be the balance of LSSKY
        /// held in the assigned urn
        uint256 stakedBalance;

        /// @dev The total amount of SKY staked in the farm across
        /// all stakers
        /// If no farm is chosen, this will be the total supply of LSSKY
        uint256 totalSupply;

        /// @dev The current rate of emissions from the farm
        /// If no farm is chosen, this will be zero
        uint256 rewardRate;

        /// @dev The amount of emissions earned which can
        /// currently be claimed.
        /// If no farm is chosen, this will be zero
        uint256 unclaimedRewards;        
    }

    /** 
     * @notice A helper to show the current positions for a set of farm indexes.
     * @dev If the farmIndex is not valid/removed that item will remain 
     * empty
     */
    function farmDetails(uint32[] calldata farmIndexes) external view returns (
        FarmDetails[] memory
    );

    /**
     * @notice Return the current SKY balance staked in the lockstake engine
     */
    function stakedBalance() external view returns (uint256);
}
