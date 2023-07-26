pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/staking/IOrigamiInvestmentManager.sol)

interface IOrigamiInvestmentManager {
    event PerformanceFeesCollected(address indexed token, uint256 amount, address indexed feeCollector);

    function rewardTokensList() external view returns (address[] memory tokens);
    function harvestRewards(bytes calldata harvestParams) external;
    function harvestableRewards() external view returns (uint256[] memory amounts);
    function projectedRewardRates(bool subtractPerformanceFees) external view returns (uint256[] memory amounts);
}
