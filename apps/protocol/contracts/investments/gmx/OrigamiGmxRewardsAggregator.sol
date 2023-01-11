pragma solidity ^0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/gmx/OrigamiGmxRewardsAggregator.sol)

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {IOrigamiInvestmentManager} from "../../interfaces/investments/IOrigamiInvestmentManager.sol";
import {IOrigamiInvestmentVault} from "../../interfaces/investments/IOrigamiInvestmentVault.sol";
import {IOrigamiGmxManager} from "../../interfaces/investments/gmx/IOrigamiGmxManager.sol";
import {IOrigamiGmxEarnAccount} from "../../interfaces/investments/gmx/IOrigamiGmxEarnAccount.sol";
import {CommonEventsAndErrors} from "../../common/CommonEventsAndErrors.sol";
import {FractionalAmount} from "../../common/FractionalAmount.sol";

/// @title Origami GMX/GLP Rewards Aggregator
/// @notice Manages the collation and selection of GMX.io rewards sources to the correct Origami investment vault.
/// ie the Origami GMX vault and the Origami GLP vault
/// @dev This implements the IOrigamiInvestmentManager interface -- the Origami GMX/GLP Rewards Distributor 
/// calls to harvest aggregated rewards.
contract OrigamiGmxRewardsAggregator is IOrigamiInvestmentManager, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @notice The type of vault this aggregator is for - either GLP or GMX.
     * The ovGLP vault gets compounding rewards from:
     *    1/ 'staked GLP'
     * The ovGMX vault gets compounding rewards from:
     *    2/ 'staked GMX'
     *    3/ 'staked GMX/esGMX/mult points' where that GMX/esGMX/mult points was earned from the staked GMX (2)
     *    4/ 'staked GMX/esGMX/mult points' where that GMX/esGMX/mult points was earned from the staked GLP (1)
     */
    IOrigamiGmxEarnAccount.VaultType public vaultType;

    /// @notice The Origami contract managing the holdings of staked GMX derived rewards
    /// @dev The GMX Vault needs to pick staked GMX/esGMX/mult point rewards from both GMX Manager and also GLP Manager 
    IOrigamiGmxManager public gmxManager;

    /// @notice The Origami contract managing the holdings of staked GLP derived rewards
    /// @dev The GLP Vault picks staked GLP rewards from the GLP manager. 
    /// The GMX vault picks staked GMX/esGMX/mult points from the GLP Manager
    IOrigamiGmxManager public glpManager;

    /// @notice The set of reward tokens that the GMX manager yields to users.
    /// [ ETH/AVAX, oGMX ]
    address[] public rewardTokens;

    /// @notice The contract/EOA responsible for harvesting rewards and distributing to the staking contract.
    address public rewardsDistributor;

    /// @notice The ovToken that rewards will compound into when harvested/swapped. 
    IOrigamiInvestmentVault public immutable ovToken;
    
    event OrigamiGmxManagersSet(IOrigamiGmxEarnAccount.VaultType _vaultType, address indexed gmxManager, address indexed glpManager);
    event RewardsDistributorSet(address indexed rewardsDistributor);
    error OnlyRewardsDistributor(address caller);

    constructor(IOrigamiGmxEarnAccount.VaultType _vaultType, address _gmxManager, address _glpManager, address _ovToken) {
        vaultType = _vaultType;
        gmxManager = IOrigamiGmxManager(_gmxManager);
        glpManager = IOrigamiGmxManager(_glpManager);
        rewardTokens = vaultType == IOrigamiGmxEarnAccount.VaultType.GLP
            ? glpManager.rewardTokensList() 
            : gmxManager.rewardTokensList();
        ovToken = IOrigamiInvestmentVault(_ovToken);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /// @notice Set the Origami GMX Manager contract used to apply GMX to earn rewards.
    function setOrigamiGmxManagers(
        IOrigamiGmxEarnAccount.VaultType _vaultType, 
        address _gmxManager, 
        address _glpManager
    ) external onlyOwner {
        vaultType = _vaultType;
        gmxManager = IOrigamiGmxManager(_gmxManager);
        glpManager = IOrigamiGmxManager(_glpManager);
        emit OrigamiGmxManagersSet(_vaultType, _gmxManager, _glpManager);
    }

    /// @notice Set the Origami staking and rewards distributor contracts.
    function setRewardsDistributor(address _rewardsDistributor) external onlyOwner {
        if (_rewardsDistributor == address(0)) revert CommonEventsAndErrors.InvalidAddress(address(0));
        rewardsDistributor = _rewardsDistributor;
        emit RewardsDistributorSet(_rewardsDistributor);
    }

    /// @notice The set of reward tokens we give to the staking contract.
    /// @dev Part of the IOrigamiInvestmentManager interface
    function rewardTokensList() external view override returns (address[] memory tokens) {
        return rewardTokens;
    }

    /// @notice The amount of rewards up to this block that Origami is due to harvest ready for compounding
    /// ie the net amount after Origami has deducted it's fees.
    /// @dev Part of the IOrigamiInvestmentManager interface.
    /// Performance fees are not deducted from these amounts.
    function harvestableRewards() external override view returns (uint256[] memory amounts) {
        // Pull the GLP manager rewards - for both GMX and GLP vaults
        amounts = glpManager.harvestableRewards(vaultType);

        // Pull the GMX manager rewards - only relevant for the GMX vault
        uint256 i;
        if (vaultType == IOrigamiGmxEarnAccount.VaultType.GMX) {
            uint256[] memory _gmxAmounts = gmxManager.harvestableRewards(vaultType);
            for (; i < rewardTokens.length; ++i) {
                amounts[i] += _gmxAmounts[i];
            }
        }

        // And also add in any not-yet-distributed harvested amounts (ie if gmxManager.harvestRewards() was called directly),
        // and sitting in this adggregator, but not yet sent to the rewardsDistributor.
        for (i=0; i < rewardTokens.length; ++i) {
            amounts[i] += IERC20(rewardTokens[i]).balanceOf(address(this));
        }
    }

    /// @notice The current native token and oGMX reward rates per second
    /// @dev Based on the current total Origami rewards, minus any portion of performance fees which Origami receives
    /// will take.
    function projectedRewardRates(bool subtractPerformanceFees) external view override returns (uint256[] memory amounts) {
        // Pull the GLP manager rewards - for both GMX and GLP vaults
        amounts = glpManager.projectedRewardRates(vaultType);

        // Pull the GMX manager rewards - only relevant for the GMX vault
        uint256 i;
        if (vaultType == IOrigamiGmxEarnAccount.VaultType.GMX) {
            uint256[] memory _gmxAmounts = gmxManager.projectedRewardRates(vaultType);
            for (; i < rewardTokens.length; ++i) {
                amounts[i] += _gmxAmounts[i];
            }
        }

        // Remove any performance fees as users aren't due these.
        if (subtractPerformanceFees) {
            (uint128 feeNumerator, uint128 feeDenominator) = ovToken.performanceFee();
            for (i=0; i < rewardTokens.length; ++i) {
                (, amounts[i]) = FractionalAmount.split(feeNumerator, feeDenominator, amounts[i]);
            }
        } 
    }

    /**
     * @notice Harvest any Origami claimable rewards distributable to users from the glpManager and gmxManager.
     * Performance fees are not collected here, they are collected after the rewards have been converted into the
     * Origami Investment token.
     */
    function harvestRewards() external override whenNotPaused returns (uint256[] memory amounts) {
        if (msg.sender != rewardsDistributor) revert OnlyRewardsDistributor(msg.sender);

        // Pull the GLP manager rewards - for both GMX and GLP vaults
        glpManager.harvestRewards();

        // The GLP vault doesn't need to harvest from the GMX vault - it won't have any rewards.
        if (vaultType == IOrigamiGmxEarnAccount.VaultType.GMX) {
            gmxManager.harvestRewards();
        }

        // Pull the GMX manager rewards - only relevant for the GMX vault
        // Then transfer any accrued balance of each reward token to the rewardsDistributor
        IERC20 rewardToken;
        uint256 amount;
        amounts = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            rewardToken = IERC20(rewardTokens[i]);
            amount = rewardToken.balanceOf(address(this));
            amounts[i] = amount;
            if (amount > 0) {
                rewardToken.safeTransfer(rewardsDistributor, amount);
            }
        }
    }

    /// @notice Owner can recover tokens
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
        emit CommonEventsAndErrors.TokenRecovered(_to, _token, _amount);
    }
}
