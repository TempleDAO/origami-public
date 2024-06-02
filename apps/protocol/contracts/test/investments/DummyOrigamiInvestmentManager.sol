pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOrigamiInvestmentManager } from "contracts/interfaces/investments/IOrigamiInvestmentManager.sol";
import { IOrigamiInvestmentVault } from "contracts/interfaces/investments/IOrigamiInvestmentVault.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";

contract DummyOrigamiInvestmentManager is IOrigamiInvestmentManager {
    using SafeERC20 for IERC20;
    using OrigamiMath for uint256;

    address[] public rewardTokens;

    uint256 public lastDistributionTime;
    
    mapping(address => uint256) public tokensPerInterval;

    IOrigamiInvestmentVault public immutable ovToken;

    constructor(
        address[] memory _rewardTokens, 
        uint256[] memory _rewardsPerInterval,
        address _ovToken
    ) {
        lastDistributionTime = block.timestamp;
        rewardTokens = _rewardTokens;
        for (uint256 i=0; i < _rewardTokens.length; i++) {
            tokensPerInterval[_rewardTokens[i]] = _rewardsPerInterval[i];
        }
        ovToken = IOrigamiInvestmentVault(_ovToken);
    }

    function rewardTokensList() external override view returns (address[] memory tokens) {
        return rewardTokens;
    }

    function harvestRewards(bytes calldata /*harvestParams*/) external override {
        uint256[] memory amounts = _pendingRewards();
        lastDistributionTime = block.timestamp;

        // Send the amount to the caller.
        // In the real world, this would be limited to be called only by the RewardDistributor
        // but we don't care for the test.
        IERC20 token;
        for (uint256 i; i<rewardTokens.length; i++) {
            token = IERC20(rewardTokens[i]);
            token.safeTransfer(msg.sender, amounts[i]);
        }
    }

    function harvestableRewards() external override view returns (uint256[] memory amounts) {
        return _pendingRewards();
    }

    function projectedRewardRates(bool subtractPerformanceFees) external override view returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);
        for (uint256 i; i < rewardTokens.length; ++i) {
            amounts[i] = tokensPerInterval[rewardTokens[i]];
        }

        // Remove any performance fees as users aren't due these.
        if (subtractPerformanceFees) {
            uint256 feeRate = ovToken.performanceFee();
            for (uint256 i; i < rewardTokens.length; ++i) {
                amounts[i] = amounts[i].subtractBps(feeRate, OrigamiMath.Rounding.ROUND_DOWN);
            }
        }
    }

    function _pendingRewards() internal view returns (uint256[] memory amounts) {
        amounts = new uint256[](rewardTokens.length);

        uint256 timeDiff = block.timestamp - lastDistributionTime;
        if (timeDiff == 0) {
            return amounts;
        }

        for (uint256 i; i < rewardTokens.length; ++i) {
            amounts[i] = tokensPerInterval[rewardTokens[i]] * timeDiff;
        }
    }

}
