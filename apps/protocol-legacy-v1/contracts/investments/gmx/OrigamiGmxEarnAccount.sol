pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGmxEarnAccount.sol)

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IGmxRewardRouter} from "../../interfaces/external/gmx/IGmxRewardRouter.sol";
import {IGmxRewardTracker} from "../../interfaces/external/gmx/IGmxRewardTracker.sol";
import {IGmxRewardDistributor} from "../../interfaces/external/gmx/IGmxRewardDistributor.sol";
import {IGmxVester} from "../../interfaces/external/gmx/IGmxVester.sol";
import {IGlpManager} from "../../interfaces/external/gmx/IGlpManager.sol";
import {IOrigamiGmxEarnAccount} from "../../interfaces/investments/gmx/IOrigamiGmxEarnAccount.sol";

import {FractionalAmount} from "../../common/FractionalAmount.sol";
import {Operators} from "../../common/access/Operators.sol";
import {GovernableUpgradeable} from "../../common/access/GovernableUpgradeable.sol";

/// @title Origami's account used for earning rewards for staking GMX/GLP 
/// @notice The Origami contract responsible for managing GMX/GLP staking and harvesting/compounding rewards.
/// This contract is kept relatively simple acting as a proxy to GMX.io staking/unstaking/rewards collection/etc,
/// as it would be difficult to upgrade (multiplier points may be burned which would be detrimental to the product).
/// @dev The Gov will be the Origami Timelock, and only gov is able to upgrade.
/// The Operators will be the OrigamiGmxManager and OrigamiGmxLocker/OrigamiGlpLocker
contract OrigamiGmxEarnAccount is IOrigamiGmxEarnAccount, Initializable, GovernableUpgradeable, Operators, UUPSUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Note: The below contracts are GMX.io contracts which can be found
    // here: https://gmxio.gitbook.io/gmx/contracts

    /// @notice $GMX
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable gmxToken;

    /// @notice $esGMX - escrowed GMX
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable esGmxToken;

    /// @notice $wrappedNative - wrapped ETH/AVAX
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20Upgradeable public immutable wrappedNativeToken; 

    /// @notice $bnGMX - otherwise known as multiplier points.
    address public bnGmxAddr;
 
    /// @notice The GMX contract used to stake, unstake claim GMX, esGMX, multiplier points
    IGmxRewardRouter public gmxRewardRouter;

    /// @notice The GMX contract used to buy and sell GLP
    IGmxRewardRouter public glpRewardRouter;

    /// @notice The GMX contract which manages the staking of GMX and esGMX, and outputs rewards as esGMX
    IGmxRewardTracker public stakedGmxTracker;

    /// @notice The GMX contract which manages the staking of GMX, esGMX, multiplier points and outputs rewards as wrappedNative (eg ETH/AVAX)
    IGmxRewardTracker public feeGmxTracker;

    /// @notice The GMX contract which manages the staking of GLP, and outputs rewards as esGMX
    IGmxRewardTracker public stakedGlpTracker;

    /// @notice The GMX contract which manages the staking of GLP, and outputs rewards as wrappedNative (eg ETH/AVAX)
    IGmxRewardTracker public feeGlpTracker;

    /// @notice The GMX contract which can transfer staked GLP from one user to another.
    IERC20Upgradeable public override stakedGlp;

    /// @notice The GMX contract which accepts deposits of esGMX to vest into GMX (linearly over 1 year).
    /// This is a separate instance when the esGMX is obtained via staked GLP, vs staked GMX
    IGmxVester public esGmxVester;
 
    /// @notice Whether GLP purchases are currently paused
    bool public override glpInvestmentsPaused;

    /// @notice The last timestamp that staked GLP was transferred out of this account.
    uint256 public override glpLastTransferredAt;

    struct GmxPositions {
        uint256 unstakedGmx;
        uint256 stakedGmx;
        uint256 unstakedEsGmx;
        uint256 stakedEsGmx;
        uint256 stakedMultiplierPoints;
        uint256 claimableNative;
        uint256 claimableEsGmx;
        uint256 claimableMultPoints;
        uint256 vestingEsGmx;
        uint256 claimableVestedGmx;
    }

    struct GlpPositions {
        uint256 stakedGlp;
        uint256 claimableNative;
        uint256 claimableEsGmx;
        uint256 vestingEsGmx;
        uint256 claimableVestedGmx;
    }

    error GlpInvestmentsPaused();

    event StakedGlpTransferred(address receiver, uint256 amount);
    event SetGlpInvestmentsPaused(bool pause);

    event RewardsHarvested(
        uint256 wrappedNativeFromGmx,
        uint256 wrappedNativeFromGlp,
        uint256 esGmxFromGmx,
        uint256 esGmxFromGlp,
        uint256 vestedGmx,
        uint256 esGmxVesting
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address gmxRewardRouterAddr) {
        _disableInitializers();

        IGmxRewardRouter _gmxRewardRouter = IGmxRewardRouter(gmxRewardRouterAddr);
        gmxToken = IERC20Upgradeable(_gmxRewardRouter.gmx());
        esGmxToken = IERC20Upgradeable(_gmxRewardRouter.esGmx());
        wrappedNativeToken = IERC20Upgradeable(_gmxRewardRouter.weth());
    }

    function initialize(address _initialGov, address _gmxRewardRouter, address _glpRewardRouter, address _esGmxVester, address _stakedGlp) initializer external {
        __Governable_init(_initialGov);
        __UUPSUpgradeable_init();

        _initGmxContracts(_gmxRewardRouter, _glpRewardRouter, _esGmxVester, _stakedGlp);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyGov
        override
    {}

    function _initGmxContracts(
        address _gmxRewardRouter, 
        address _glpRewardRouter, 
        address _esGmxVester, 
        address _stakedGlp
    ) internal {
        // Copy the required addresses from the GMX Reward Router.
        gmxRewardRouter = IGmxRewardRouter(_gmxRewardRouter);
        glpRewardRouter = IGmxRewardRouter(_glpRewardRouter);
        bnGmxAddr = gmxRewardRouter.bnGmx();
        stakedGmxTracker = IGmxRewardTracker(gmxRewardRouter.stakedGmxTracker());
        feeGmxTracker = IGmxRewardTracker(gmxRewardRouter.feeGmxTracker());
        stakedGlpTracker = IGmxRewardTracker(glpRewardRouter.stakedGlpTracker());
        feeGlpTracker = IGmxRewardTracker(glpRewardRouter.feeGlpTracker());
        stakedGlp = IERC20Upgradeable(_stakedGlp);
        esGmxVester = IGmxVester(_esGmxVester);
    }

    /// @dev In case any of the upstream GMX contracts are upgraded this can be re-initialized.
    function initGmxContracts(
        address _gmxRewardRouter, 
        address _glpRewardRouter, 
        address _esGmxVester, 
        address _stakedGlp
    ) external onlyGov {
        _initGmxContracts(
            _gmxRewardRouter, 
            _glpRewardRouter, 
            _esGmxVester, 
            _stakedGlp
        );
    }

    function addOperator(address _address) external override onlyGov {
        _addOperator(_address);
    }

    function removeOperator(address _address) external override onlyGov {
        _removeOperator(_address);
    }

    /// @notice Stake any $GMX that this contract holds at GMX.io
    function stakeGmx(uint256 _amount) external override onlyOperators {
        // While the gmxRewardRouter is the contract which we call to stake, $GMX allowance
        // needs to be provided to the stakedGmxTracker as it pulls/stakes the $GMX.
        gmxToken.safeIncreaseAllowance(address(stakedGmxTracker), _amount);
        gmxRewardRouter.stakeGmx(_amount);
    }

    /// @notice Unstake $GMX from GMX.io and send to the operator
    /// @dev This will burn any aggregated multiplier points, so should be avoided where possible.
    function unstakeGmx(uint256 _amount) external override onlyOperators {
        gmxRewardRouter.unstakeGmx(_amount);
        gmxToken.safeTransfer(msg.sender, _amount);
    }

    /// @notice Stake any $esGMX that this contract holds at GMX.io
    function stakeEsGmx(uint256 _amount) external onlyOperators {
        // While the gmxRewardRouter is the contract which we call to stake, $esGMX allowance
        // needs to be provided to the stakedGmxTracker as it pulls/stakes the $esGMX.
        esGmxToken.safeIncreaseAllowance(address(stakedGmxTracker), _amount);
        gmxRewardRouter.stakeEsGmx(_amount);
    }

    /// @notice Unstake $esGMX from GMX.io - this doesn't send esGMX to the operator as it's non-transferable.
    /// @dev This will burn any aggregated multiplier points, so should be avoided where possible.
    function unstakeEsGmx(uint256 _amount) external onlyOperators {
        gmxRewardRouter.unstakeEsGmx(_amount);
    }

    /// @notice Buy and stake $GLP using GMX.io's contracts using a whitelisted token.
    /// @dev GMX.io takes fees dependent on the pool constituents.
    function mintAndStakeGlp(uint256 fromAmount, address fromToken, uint256 minUsdg, uint256 minGlp) external override onlyOperators returns (uint256) {
        if (glpInvestmentsPaused) revert GlpInvestmentsPaused();

        IERC20Upgradeable(fromToken).safeIncreaseAllowance(glpRewardRouter.glpManager(), fromAmount);
        return glpRewardRouter.mintAndStakeGlp(
            fromToken, 
            fromAmount, 
            minUsdg, 
            minGlp
        );
    }

    /// @notice Unstake and sell $GLP using GMX.io's contracts, to a whitelisted token.
    /// @dev GMX.io takes fees dependent on the pool constituents.
    function unstakeAndRedeemGlp(uint256 glpAmount, address toToken, uint256 minOut, address receiver) external override onlyOperators returns (uint256) {
        return glpRewardRouter.unstakeAndRedeemGlp(
            toToken, 
            glpAmount, 
            minOut, 
            receiver
        );
    }

    /// @notice Transfer staked $GLP to another receiver. This will unstake from this contract and restake to another user.
    function transferStakedGlp(uint256 glpAmount, address receiver) external override onlyOperators {
        stakedGlp.safeTransfer(receiver, glpAmount);
        emit StakedGlpTransferred(receiver, glpAmount);
    }

    /// @notice When this contract is free to exit a GLP position, a cooldown period after the latest GLP purchase
    function glpInvestmentCooldownExpiry() public override view returns (uint256) {
        IGlpManager glpManager = IGlpManager(glpRewardRouter.glpManager());
        return glpManager.lastAddedAt(address(this)) + glpManager.cooldownDuration();
    }
    
    function _setGlpInvestmentsPaused(bool pause) internal {
        glpInvestmentsPaused = pause;
        emit SetGlpInvestmentsPaused(pause);
    }

    /// @notice Attempt to transfer staked $GLP to another receiver. This will unstake from this contract and restake to another user.
    /// @dev If the transfer cannot happen in this transaction due to the GLP cooldown
    /// then future GLP deposits will be paused such that it can be attempted again.
    /// When the transfer succeeds in the future, deposits will be unpaused.
    function transferStakedGlpOrPause(uint256 glpAmount, address receiver) external override onlyOperators {
        uint256 cooldownExpiry = glpInvestmentCooldownExpiry();

        if (block.timestamp > cooldownExpiry) {
            glpLastTransferredAt = block.timestamp;
            emit StakedGlpTransferred(receiver, glpAmount);

            if (glpInvestmentsPaused) {
                _setGlpInvestmentsPaused(false);
            }

            stakedGlp.safeTransfer(receiver, glpAmount);
        } else if (!glpInvestmentsPaused) {
            _setGlpInvestmentsPaused(true);
        }
    }

    /// @notice The current wrappedNative and esGMX rewards per second
    /// @dev This includes any boost to wrappedNative (ie ETH/AVAX) from staked multiplier points.
    /// @param vaultType If for GLP, get the reward rates for just staked GLP rewards. If GMX get the reward rates for combined GMX/esGMX/mult points
    /// for Origami's share of the upstream GMX.io rewards.
    function rewardRates(VaultType vaultType) external override view returns (
        uint256 wrappedNativeTokensPerSec,
        uint256 esGmxTokensPerSec
    ) {
        if (vaultType == VaultType.GLP) {
            wrappedNativeTokensPerSec = _rewardsPerSec(feeGlpTracker);
            esGmxTokensPerSec = _rewardsPerSec(stakedGlpTracker);
        } else {
            wrappedNativeTokensPerSec = _rewardsPerSec(feeGmxTracker);
            esGmxTokensPerSec = _rewardsPerSec(stakedGmxTracker);
        }
    }

    /// @notice The amount of $esGMX and $Native (ETH/AVAX) which are claimable by Origami as of now
    /// @param vaultType If GLP, get the reward rates for just staked GLP rewards. If GMX get the reward rates for combined GMX/esGMX/mult points
    /// @dev This is composed of both the staked GMX and staked GLP rewards that this account may hold
    function harvestableRewards(VaultType vaultType) external view override returns (
        uint256 wrappedNativeAmount, 
        uint256 esGmxAmount
    ) {
        if (vaultType == VaultType.GLP) {
            wrappedNativeAmount = feeGlpTracker.claimable(address(this));
            esGmxAmount = stakedGlpTracker.claimable(address(this));
        } else {
            wrappedNativeAmount = feeGmxTracker.claimable(address(this));
            esGmxAmount = stakedGmxTracker.claimable(address(this));
        }
    }

    /**
     * @notice This earn account's current positions at GMX.io
     */
    function positions() external view returns (GmxPositions memory gmxPositions, GlpPositions memory glpPositions) {
        // GMX
        gmxPositions.unstakedGmx = gmxToken.balanceOf(address(this));
        gmxPositions.stakedGmx = stakedGmxTracker.depositBalances(address(this), address(gmxToken));
        gmxPositions.unstakedEsGmx = esGmxToken.balanceOf(address(this));
        gmxPositions.stakedEsGmx = stakedGmxTracker.depositBalances(address(this), address(esGmxToken));
        gmxPositions.stakedMultiplierPoints = feeGmxTracker.depositBalances(address(this), bnGmxAddr);
        gmxPositions.claimableNative = feeGmxTracker.claimable(address(this));
        gmxPositions.claimableEsGmx = stakedGmxTracker.claimable(address(this));
        gmxPositions.claimableMultPoints = IGmxRewardTracker(gmxRewardRouter.bonusGmxTracker()).claimable(address(this));
        gmxPositions.vestingEsGmx = IGmxVester(gmxRewardRouter.gmxVester()).balanceOf(address(this));
        gmxPositions.claimableVestedGmx = IGmxVester(gmxRewardRouter.gmxVester()).claimable(address(this));

        // GLP
        glpPositions.stakedGlp = feeGlpTracker.depositBalances(address(this), gmxRewardRouter.glp());
        glpPositions.claimableNative = feeGlpTracker.claimable(address(this));
        glpPositions.claimableEsGmx = stakedGlpTracker.claimable(address(this));
        glpPositions.vestingEsGmx = IGmxVester(gmxRewardRouter.glpVester()).balanceOf(address(this));
        glpPositions.claimableVestedGmx = IGmxVester(gmxRewardRouter.glpVester()).claimable(address(this));
    }

    /// @notice Harvest all rewards, and apply compounding:
    /// - Claim all wrappedNative and send to origamiGmxManager
    /// - Claim all esGMX and:
    ///     - Deposit a portion into vesting (given by `esGmxVestingRate`)
    ///     - Stake the remaining portion
    /// - Claim all GMX from vested esGMX and send to origamiGmxManager
    /// - Stake/compound any multiplier point rewards (aka bnGmx) 
    /// @dev only the OrigamiGmxManager can call since we need to track and action based on the amounts harvested.
    function harvestRewards(FractionalAmount.Data calldata _esGmxVestingRate) external onlyOperators override returns (
        ClaimedRewards memory claimedRewards
    ) {
        claimedRewards = _handleGmxRewards(
            HandleGmxRewardParams({
                shouldClaimGmx: true, /* claims any vested GMX. */
                shouldStakeGmx: false, /* The OrigamiGmxManager will decide where to stake the vested GMX */
                shouldClaimEsGmx: true,  /* Always claim esGMX rewards */
                shouldStakeEsGmx: false, /* Manually stake/vest these after */
                shouldStakeMultiplierPoints: true,  /* Always claim and stake mult point rewards */
                shouldClaimWeth: true  /* Always claim weth/wavax rewards */
            }),
            msg.sender
        );

        // Vest & Stake esGMX     
        uint256 esGmxVesting;   
        {
            uint256 totalEsGmxClaimed = claimedRewards.esGmxFromGmx + claimedRewards.esGmxFromGlp;

            if (totalEsGmxClaimed != 0) {
                uint256 esGmxReinvested;
                (esGmxVesting, esGmxReinvested) = FractionalAmount.split(_esGmxVestingRate, totalEsGmxClaimed);

                // Vest a portion of esGMX
                if (esGmxVesting != 0) {
                    // There's a limit on how much we are allowed to vest at GMX.io, based on the rewards which
                    // have been earnt vs how much has been staked already.
                    // So use the min(requested, allowed)
                    uint256 maxAllowedToVest = esGmxVester.getMaxVestableAmount(address(this));
                    uint256 alreadyVesting = esGmxVester.getTotalVested(address(this));                   
                    uint256 remainingAllowedToVest = subtractWithFloorAtZero(maxAllowedToVest, alreadyVesting);
                    
                    if (esGmxVesting > remainingAllowedToVest) {
                        esGmxVesting = remainingAllowedToVest;
                        esGmxReinvested = totalEsGmxClaimed - remainingAllowedToVest;                        
                    }

                    // Deposit the amount to vest in the vesting contract.
                    if (esGmxVesting != 0) {
                        esGmxVester.deposit(esGmxVesting);
                    }
                }

                // Stake the remainder.
                if (esGmxReinvested != 0) {
                    gmxRewardRouter.stakeEsGmx(esGmxReinvested);
                }
            }
        }

        emit RewardsHarvested(
            claimedRewards.wrappedNativeFromGmx,
            claimedRewards.wrappedNativeFromGlp,
            claimedRewards.esGmxFromGmx,
            claimedRewards.esGmxFromGlp,
            claimedRewards.vestedGmx,
            esGmxVesting
        );
    }

    /// @notice Pass-through handleRewards() for harvesting/compounding rewards.
    function handleRewards(HandleGmxRewardParams memory params) external override onlyOperators returns (ClaimedRewards memory claimedRewards) {
        return _handleGmxRewards(params, msg.sender);
    }

    function _handleGmxRewards(HandleGmxRewardParams memory params, address _receiver) internal returns (ClaimedRewards memory claimedRewards) {
        // Check balances before/after in order to check how many wrappedNative, esGMX, mult points, GMX
        // were harvested.
        uint256 gmxBefore; 
        uint256 esGmxBefore;
        uint256 wrappedNativeBefore;
        {
            if (params.shouldClaimGmx && !params.shouldStakeGmx) {
                gmxBefore = gmxToken.balanceOf(address(this));
            }

            if (params.shouldClaimEsGmx && !params.shouldStakeEsGmx) {
                esGmxBefore = esGmxToken.balanceOf(address(this));
                // Find how much esGMX harvested from the GLP tracker from the 'claimable'
                // Then any balance of actual claimed is for the GMX tracker.
                claimedRewards.esGmxFromGlp = stakedGlpTracker.claimable(address(this));
            }
            
            if (params.shouldClaimWeth) {
                wrappedNativeBefore = wrappedNativeToken.balanceOf(address(this));
                // Find how much wETH/wAVAX harvested from the GLP tracker from the 'claimable'
                // Then any balance of actual claimed is for the GMX tracker.
                claimedRewards.wrappedNativeFromGlp = feeGlpTracker.claimable(address(this));
            }
        }

        gmxRewardRouter.handleRewards(
            params.shouldClaimGmx,
            params.shouldStakeGmx,
            params.shouldClaimEsGmx,
            params.shouldStakeEsGmx,
            params.shouldStakeMultiplierPoints,
            params.shouldClaimWeth,
            false  /* Never convert to raw ETH */
        );

        // Update accounting and transfer tokens.
        {
            // Calculate how many GMX were claimed from vested esGMX, and send to the receiver
            if (params.shouldClaimGmx && !params.shouldStakeGmx) {
                claimedRewards.vestedGmx = gmxToken.balanceOf(address(this)) - gmxBefore;
                if (claimedRewards.vestedGmx != 0) {
                    gmxToken.safeTransfer(_receiver, claimedRewards.vestedGmx);
                }
            }

            // Calculate how many esGMX rewards were claimed
            // esGMX is effectively non-transferrable
            if (params.shouldClaimEsGmx && !params.shouldStakeEsGmx) {
                uint256 claimed = esGmxToken.balanceOf(address(this)) - esGmxBefore;
                claimedRewards.esGmxFromGmx = subtractWithFloorAtZero(claimed, claimedRewards.esGmxFromGlp);
            }

            // Calculate how many ETH rewards were awarded and send to the receiver
            if (params.shouldClaimWeth) {
                uint256 claimed = wrappedNativeToken.balanceOf(address(this)) - wrappedNativeBefore;
                claimedRewards.wrappedNativeFromGmx = subtractWithFloorAtZero(claimed, claimedRewards.wrappedNativeFromGlp);
                if (claimed != 0) {
                    wrappedNativeToken.safeTransfer(_receiver, claimed);
                }
            }
        }
    }

    function subtractWithFloorAtZero(uint256 lhs, uint256 rhs) internal pure returns (uint256) {
        unchecked {
            return (lhs > rhs) ? lhs - rhs : 0;
        }
    }

    /// @notice Pass-through deposit esGMX into the vesting contract.
    /// May be required for manual operations / future automation
    function depositIntoEsGmxVesting(address _esGmxVester, uint256 _amount) external onlyOperators {
        IGmxVester(_esGmxVester).deposit(_amount);
    }

    /// @notice Pass-through withdraw from the esGMX vesting contract.
    /// May be required for manual operations / future automation
    /// @dev This can only withdraw the full amount only
    function withdrawFromEsGmxVesting(address _esGmxVester) external onlyOperators {
        IGmxVester(_esGmxVester).withdraw();
    }

    /// @dev Origamis share of the underlying GMX reward distributor's total 
    /// rewards per second
    function _rewardsPerSec(IGmxRewardTracker rewardTracker) internal view returns (uint256) {
        uint256 supply = rewardTracker.totalSupply();
        if (supply == 0) return 0;

        return (
            IGmxRewardDistributor(rewardTracker.distributor()).tokensPerInterval() * 
            rewardTracker.stakedAmounts(address(this)) /
            supply
        );
    }

}