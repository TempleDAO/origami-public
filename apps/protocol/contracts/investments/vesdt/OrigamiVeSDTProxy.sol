pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/vesdt/OrigamiVeSDTProxy.sol)

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IStakeDao_VeSDT} from "contracts/interfaces/external/stakedao/IStakeDao_VeSDT.sol";
import {IStakeDao_VeSDTRewardsDistributor} from "contracts/interfaces/external/stakedao/IStakeDao_VeSDTRewardsDistributor.sol";
import {IStakeDao_ClaimRewards} from "contracts/interfaces/external/stakedao/IStakeDao_ClaimRewards.sol";
import {IStakeDao_GaugeController} from "contracts/interfaces/external/stakedao/IStakeDao_GaugeController.sol";
import {IStakeDao_LiquidityGaugeV4} from "contracts/interfaces/external/stakedao/IStakeDao_LiquidityGaugeV4.sol";
import {IStakeDao_VeBoost} from "contracts/interfaces/external/stakedao/IStakeDao_VeBoost.sol";
import {ISnapshotDelegator} from "contracts/interfaces/external/snapshot/ISnapshotDelegator.sol";

import {Operators} from "contracts/common/access/Operators.sol";
import {CommonEventsAndErrors} from "contracts/common/CommonEventsAndErrors.sol";
import {GovernableUpgradeable} from "../../common/access/GovernableUpgradeable.sol";

/**
  * @title Origami veSDT Proxy
  * @notice A proxy to handle:
  *       - Locking $SDT into $veSDT (and withdrawing)
  *       - Claiming veSDT rewards
  *       - Claiming rewards from staked sdToken gauges (Liquid Locker & Strategy)
  *       - Voting for gauges
  *       - Meta-governance delegation (snapshot)
  *       - veBoost delegation
  * @dev staked $sdTokens (eg sdCRV-gauge) will be obtained externally - HW/msig/etc - and transferred to this account.
  */
contract OrigamiVeSDTProxy is Initializable, GovernableUpgradeable, Operators, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    /// @notice The vote escrowed SDT token
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakeDao_VeSDT public immutable veSDT;

    /// @dev The Stake DAO SDT token
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable sdtToken;

    /// @notice Used to checkpoint and claim veSDT rewards
    IStakeDao_VeSDTRewardsDistributor public veSDTRewardsDistributor;
    
    /// @notice Used to claim rewards for Locker and Strategies
    IStakeDao_ClaimRewards public gaugeRewardsClaimer;

    /// @notice Used to vote for a Liquid Locker (gov) gauge using veSDT voting power
    IStakeDao_GaugeController public sdtLockerGaugeController;

    /// @notice Used to vote for a Strategy (LP) gauge using veSDT voting power
    IStakeDao_GaugeController public sdtStrategiesGaugeController;

    /// @notice Used to delegate votes for metagovernance
    ISnapshotDelegator public snapshotDelegateRegistry;

    /// @notice Used to delegate veSDT rewards boost to another address
    IStakeDao_VeBoost public veBoost;

    event SDTStrategiesGaugeControllerSet(address indexed strategiesGaugeController);
    event SDTLockerGaugeControllerSet(address indexed lockerGaugeController);
    event GaugeRewardsClaimerSet(address indexed gaugeRewardsClaimer);
    event SnapshotDelegateRegistrySet(address indexed snapshotDelegateRegistry);
    event VeSDTRewardsDistributorSet(address indexed rewardsDistributor);
    event VeBoostSet(address indexed veBoost);

    event VeSDTWithdrawn(address indexed to, uint256 amount);
    event VeSDTRewardsClaimed(address indexed user, uint256 amount, address indexed token_address);
    event GaugeRewardsClaimed(address[] _gauges, address _claimTo);
    event GaugeRewardsClaimedAndLocked(address[] _gauges, address _claimTo);
    event MetagovernanceSetDelegate(bytes32 indexed id, address indexed delegate);
    event MetagovernanceClearDelegate(bytes32 indexed id);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount);

    error CannotEstimateClaim();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _veSDT,
        address _sdt
    ) {
        _disableInitializers();
        veSDT = IStakeDao_VeSDT(_veSDT);
        sdtToken = IERC20Upgradeable(_sdt);
    }

    function _authorizeUpgrade(address /*newImplementation*/)
        internal
        onlyGov
        override
    {}

    function initialize(
        address _initialGov, 
        address _veSDTRewardsDistributor,
        address _gaugeRewardsClaimer,
        address _sdtLockerGaugeController,
        address _sdtStrategiesGaugeController,
        address _snapshotDelegateRegistry,
        address _veBoost
    ) public initializer {
        __Governable_init(_initialGov);
        __UUPSUpgradeable_init();

        veSDTRewardsDistributor = IStakeDao_VeSDTRewardsDistributor(_veSDTRewardsDistributor);
        gaugeRewardsClaimer = IStakeDao_ClaimRewards(_gaugeRewardsClaimer);
        sdtLockerGaugeController = IStakeDao_GaugeController(_sdtLockerGaugeController);
        sdtStrategiesGaugeController = IStakeDao_GaugeController(_sdtStrategiesGaugeController);
        snapshotDelegateRegistry = ISnapshotDelegator(_snapshotDelegateRegistry);
        veBoost = IStakeDao_VeBoost(_veBoost);
    }

    function addOperator(address _address) external override onlyGov {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyGov {
        _removeOperator(_address);
    }

    /** 
      * @notice Set a new gauge controller for Stake Dao Liquid Lockers
      */
    function setSDTLockerGaugeController(address _sdtLockerGaugeController) external onlyGov {
        if (_sdtLockerGaugeController == address(0)) revert CommonEventsAndErrors.InvalidAddress(_sdtLockerGaugeController);
        sdtLockerGaugeController = IStakeDao_GaugeController(_sdtLockerGaugeController);
        emit SDTLockerGaugeControllerSet(_sdtLockerGaugeController);
    }

    /** 
      * @notice Set a new gauge controller for Stake Dao Strategies
      */
    function setSDTStrategiesGaugeController(address _sdtStrategyGaugeController) external onlyGov {
        if (_sdtStrategyGaugeController == address(0)) revert CommonEventsAndErrors.InvalidAddress(_sdtStrategyGaugeController);
        sdtStrategiesGaugeController = IStakeDao_GaugeController(_sdtStrategyGaugeController);
        emit SDTStrategiesGaugeControllerSet(_sdtStrategyGaugeController);
    }

    /** 
      * @notice Set a new veSDT rewards distributor
      */
    function setVeSDTRewardsDistributor(address _veSDTRewardsDistributor) external onlyGov {
        if (_veSDTRewardsDistributor == address(0)) revert CommonEventsAndErrors.InvalidAddress(_veSDTRewardsDistributor);
        veSDTRewardsDistributor = IStakeDao_VeSDTRewardsDistributor(_veSDTRewardsDistributor);
        emit VeSDTRewardsDistributorSet(_veSDTRewardsDistributor);
    }

    /** 
      * @notice Set a new delegate registry
      */
    function setSnapshotDelegateRegistry(address _snapshotDelegateRegistry) external onlyGov {
        if (_snapshotDelegateRegistry == address(0)) revert CommonEventsAndErrors.InvalidAddress(_snapshotDelegateRegistry);
        snapshotDelegateRegistry = ISnapshotDelegator(_snapshotDelegateRegistry);
        emit SnapshotDelegateRegistrySet(_snapshotDelegateRegistry);
    }

    /** 
      * @dev Set a new gauge rewards claimer
      */
    function setGaugeRewardsClaimer(address _gaugeRewardsClaimer) external onlyGov {
        if (_gaugeRewardsClaimer == address(0)) revert CommonEventsAndErrors.InvalidAddress(_gaugeRewardsClaimer);
        gaugeRewardsClaimer = IStakeDao_ClaimRewards(_gaugeRewardsClaimer);
        emit GaugeRewardsClaimerSet(_gaugeRewardsClaimer);
    }

    /** 
      * @dev Set a new gauge rewards claimer
      */
    function setVeBoost(address _veBoost) external onlyGov {
        if (_veBoost == address(0)) revert CommonEventsAndErrors.InvalidAddress(_veBoost);
        veBoost = IStakeDao_VeBoost(_veBoost);
        emit VeBoostSet(_veBoost);
    }

    /** 
      * @notice Lock `amount` SDT tokens in the vote escroed SDT, and lock until `unlock_time`
      * @param amount Amount of SDT to lock
      * @param unlock_time Timestamp when the SDT unlocks. This will be rounded down to whole weeks
      */
    function veSDTCreateLock(uint256 amount, uint256 unlock_time) external onlyOperators {
        // Increase allowance then create lock
        sdtToken.safeIncreaseAllowance(address(veSDT), amount);
        veSDT.create_lock(amount, unlock_time);
    }

    /** 
      * @notice Lock `amount` SDT tokens in the vote escroed SDT, using the existing unlock time
      * @param amount Additional amount of SDT to lock
      */
    function veSDTIncreaseAmount(uint256 amount) external onlyOperators {
        // Increase allowance then increase the lock amount
        sdtToken.safeIncreaseAllowance(address(veSDT), amount);
        veSDT.increase_amount(amount);
    }

    /** 
      * @notice Extend the veSDT unlock time, giving higher voting power for the SDT
      * @param unlock_time New timestamp for unlocking
      */
    function veSDTIncreaseUnlockTime(uint256 unlock_time) external onlyOperators {
        veSDT.increase_unlock_time(unlock_time);
    }

    /** 
      * @notice Withdraw all unlocked SDT tokens
      * @dev Only possible if the lock has expired
      * @param receiver The address receiving the SDT
      */
    function veSDTWithdraw(address receiver) external onlyOperators {
        // Pull the lock amount (and convert to uint)
        uint256 lockedAmount = uint128(veSDT.locked(address(this)).amount);

        // An extra event here to also report the account it's sent to.
        emit VeSDTWithdrawn(receiver, lockedAmount);

        // Withdraw the SDT, and transfer.
        veSDT.withdraw();

        if (receiver != address(this)) {
            sdtToken.safeTransfer(receiver, lockedAmount);
        }
    }

    /** 
      * @notice Get the current veSDT voting balance as of now.
      */
    function veSDTVotingBalance() external view returns (uint256) {
        return veSDT.balanceOf(address(this), block.timestamp);
    }

    /** 
      * @notice Calculate total veSDT voting supply, as of now.
      */
    function totalVeSDTSupply() external view returns (uint256) {
        return veSDT.totalSupply(block.timestamp);
    }

    /** 
      * @notice Current lock details for this contract
      * @dev veSDT Will revert if no lock has been added yet.
      */
    function veSDTLocked() external view returns (IStakeDao_VeSDT.LockedBalance memory) {
        return veSDT.locked(address(this));
    }

    /**
      * @notice Claim rewards from staked veSDT, and disburse to a given address.
      */
    function veSDTClaimRewards(address receiver) external onlyOperators returns (uint256 claimed) {
        claimed = veSDTRewardsDistributor.claim(address(this));
        if (claimed != 0) {
            address rewardToken = veSDTRewardsDistributor.token();
            emit VeSDTRewardsClaimed(receiver, claimed, rewardToken);

            if (receiver != address(this)) {
                IERC20Upgradeable(rewardToken).safeTransfer(receiver, claimed);
            }
        }
    }

    // For each gauge, if there's a positive balance for any of the reserve tokens, then
    // send to the receiver.
    function transferGaugeRewardTokens(address[] calldata gauges, address receiver) internal {
        IStakeDao_LiquidityGaugeV4 gauge;
        uint256 rewardTokenCount;
        uint256 j;
        IERC20Upgradeable rewardToken;
        uint256 rewardBal;
        for (uint256 i; i < gauges.length; ++i) {
            gauge = IStakeDao_LiquidityGaugeV4(gauges[i]);
            rewardTokenCount = gauge.reward_count();
            for (j=0; j < rewardTokenCount; ++j) {
                rewardToken = IERC20Upgradeable(gauge.reward_tokens(j));
                rewardBal = rewardToken.balanceOf(address(this));
                if (rewardBal != 0) {
                    rewardToken.safeTransfer(receiver, rewardBal);
                }
            }
        }
    }

    /// @notice Claim rewards from Liquid Locker or Strategy gauges
    /// @param gauges A list of liquid locker/strategy gauges to claim from
    /// @param receiver The receiver of the rewards.
    function claimGaugeRewards(
        address[] calldata gauges,
        address receiver
    ) external onlyOperators {
        gaugeRewardsClaimer.claimRewards(gauges);
        if (receiver != address(this)) {
            transferGaugeRewardTokens(gauges, receiver);
        }
        emit GaugeRewardsClaimed(gauges, receiver);
    }

    /// @notice Claim and lock rewards from Liquid Locker or Strategy gauges (where possible)
    /// @dev SDT tokens are locked into veSDT, some gauges (eg sdCRV) can be compounded too.
    /// @dev Any tokens which can't be auto-deposited will be returned to the `receiver`
    /// @param gauges A list of liquid locker/strategy gauges to claim from
    /// @param receiver The receiver of the rewards.
    function claimAndLockGaugeRewards(
        address[] calldata gauges, 
        IStakeDao_ClaimRewards.LockStatus memory lockStatus, 
        address receiver
    ) external onlyOperators {
        gaugeRewardsClaimer.claimAndLock(gauges, lockStatus);

        // Not all the gauges support auto-locking. So transfer the remainder
        if (receiver != address(this)) {
            transferGaugeRewardTokens(gauges, receiver);
        }

        emit GaugeRewardsClaimedAndLocked(gauges, receiver);
    }

    /**
      * @notice Allocate voting power for liquid locker gauges, using veSDT balance. 
      * @dev `gauges` and `weights` must be the same size.
      * @param gauges Set of liquid locker gauges to vote for.
      * @param weights Weights for gauges in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0
      */
    function voteForSDTLockers(address[] calldata gauges, uint256[] calldata weights) external onlyOperators {
        if (gauges.length != weights.length) revert CommonEventsAndErrors.InvalidParam();
        for (uint256 i; i < gauges.length; ++i) {
            sdtLockerGaugeController.vote_for_gauge_weights(gauges[i], weights[i]);
        }
    }

    /**
      * @notice Allocate voting power for strategy gauges, using veSDT balance. 
      * @dev `gauges` and `weights` must be the same size.
      * @param gauges Set of strategy gauges to vote for.
      * @param weights Weights for gauges in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0
      */
    function voteForSDTStrategies(address[] calldata gauges, uint256[] calldata weights) external onlyOperators {
        if (gauges.length != weights.length) revert CommonEventsAndErrors.InvalidParam();
        for (uint256 i; i < gauges.length; ++i) {
            sdtStrategiesGaugeController.vote_for_gauge_weights(gauges[i], weights[i]);
        }
    }

    /// @notice Delegate the boost we get from veSDT holdings to another address.
    /// @param _to The address to give the veBoost
    /// @param _amount How much veBoost to delegate
    /// @param _endtime The end time of the delegation. This needs to be exactly divisible by `WEEK`
    function delegateVeBoost(address _to, uint256 _amount, uint256 _endtime) external onlyOperators {
        veBoost.boost(_to, _amount, _endtime, address(this));
    }

    /// @notice The current effective veBoost balance of the proxy, including any delegations (sent or received)
    function veBoostBalance() external view returns (uint256) {
        return veBoost.balanceOf(address(this));
    }

    /// @notice Delegate meta governance voting power to another address
    /// @param id The ENS address of the category of what to delegate, as bytes32 -- eg 'lido-snapshot.eth'
    /// @param delegate Who to give the voting power
    function setMetagoverananceDelegate(bytes32 id, address delegate) external onlyOperators {
        emit MetagovernanceSetDelegate(id, delegate);
        snapshotDelegateRegistry.setDelegate(id, delegate);
    }

    /// @notice Remove existing meta governance delegation
    /// @param id The ENS address of the category of what to delegate, as bytes32 -- eg 'lido-snapshot.eth'
    function clearMetagoverananceDelegate(bytes32 id) external onlyOperators {
        emit MetagovernanceClearDelegate(id);
        snapshotDelegateRegistry.clearDelegate(id);
    }

    /// @notice Transfer a token to a designated address.
    /// @dev This can be used to recover tokens, but also to transfer staked $sdToken gauge tokens, reward tokens to the DAO/another address/HW/etc
    function transferToken(address _token, address _to, uint256 _amount) external onlyOperators {
        emit TokenTransferred(_token, _to, _amount);
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }

    /// @notice Set an allowance such that a spender can pull a token. 
    /// @dev Required for future integration such that contracts can pull the staked $sdToken gauge tokens, reward tokens, etc.
    function increaseTokenAllowance(address _token, address _spender, uint256 _amount) external onlyOperators {
        IERC20Upgradeable(_token).safeIncreaseAllowance(_spender, _amount);
    }
}
