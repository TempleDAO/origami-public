pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/opal/IOpalVault.sol)

import { IOrigamiTokenizedBalanceSheetVault } from "contracts/interfaces/common/IOrigamiTokenizedBalanceSheetVault.sol";

/**
 * @title Origami Portfolio of Assets and Liabilities (OPAL) - Tokenized Balance Sheet (TBS) Vault
 * @notice The logic to aggregate the adapter balance sheets and allocate out to the adapters is delegated to a manager.
 */
interface IOpalVault is IOrigamiTokenizedBalanceSheetVault {
    event PerformanceFeeSet(uint256 fee);
    event PerformanceFeesCollected(address indexed feeCollector, uint256 mintAmount);
    event FeeCollectorSet(address indexed feeCollector);

    /// @notice Set the vault annual performance fee
    /// @dev Represented in basis points
    function setAnnualPerformanceFee(uint48 _annualPerformanceFeeBps) external;

    /// @notice Set the Origami performance fee collector address
    function setFeeCollector(address _feeCollector) external;

    /// @notice Collect the performance fees to the Origami Treasury
    function collectPerformanceFees() external returns (uint256 amount);

    /// @notice The address used to collect the Origami performance fees.
    function feeCollector() external view returns (address);

    /// @notice The annual performance fee which Origami takes from harvested rewards before compounding into reserves.
    /// @dev Represented in basis points
    function annualPerformanceFeeBps() external view returns (uint48);

    /// @notice The last time the performance fee was collected
    function lastPerformanceFeeTime() external view returns (uint48);

    /// @notice The accrued performance fee amount which would be minted as of now, based on the total supply
    function accruedPerformanceFee() external view returns (uint256);

    /// @notice The maximum possible value for the Origami performance fee
    function MAX_PERFORMANCE_FEE_BPS() external view returns (uint16);
}
