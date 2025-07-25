pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/investments/IOrigamiVestingReserves.sol)

/**
 * @title Origami Vesting Reserves
 * @notice A mix-in to have linearly dripped in reserves into the vault share price
 */
interface IOrigamiVestingReserves {
    event ReservesVestingDurationSet(uint48 durationInSeconds);

    /// @notice Duration of each vesting period
    function reservesVestingDuration() external view returns (uint48);

    /// @notice When the current vesting period started
    function lastVestingCheckpoint() external view returns (uint48);

    /// @notice Rewards which are vesting in the current period
    /// @dev Use the `vestingStatus()` in order to get accurate vested vs unvested split as 
    /// of the current block timestamp.
    /// `vestingReserves()` may still show a value > 0 even if the `block.timestamp` is
    ///  past the `lastVestingCheckpoint+reservesVestingDuration` (depending on checkpoint status)
    function vestingReserves() external view returns (uint128);

    /// @notice Accrued rewards which will start vesting in the next `reservesVestingDuration` period
    function futureVestingReserves() external view returns (uint128);

    /// @notice The breakdown of balances for the current period's vesting and any accrued for the next period
    function vestingStatus() external view returns (
        uint256 currentPeriodVested,
        uint256 currentPeriodUnvested,
        uint256 futurePeriodUnvested
    );
}
