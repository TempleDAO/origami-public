pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/OrigamiVestingReserves.sol)

import { IOrigamiVestingReserves } from "contracts/interfaces/investments/IOrigamiVestingReserves.sol";
import { OrigamiMath } from "contracts/libraries/OrigamiMath.sol";
import { SafeCast } from "contracts/libraries/SafeCast.sol";
import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";

/**
 * @title Origami Vesting Reserves
 * @notice A mix-in to have linearly dripped in reserves into the vault share price
 */
abstract contract OrigamiVestingReserves is IOrigamiVestingReserves {
    using OrigamiMath for uint256;
    using SafeCast for uint256;

    /// @inheritdoc IOrigamiVestingReserves
    uint48 public reservesVestingDuration;

    /// @inheritdoc IOrigamiVestingReserves
    uint48 public override lastVestingCheckpoint;

    /// @inheritdoc IOrigamiVestingReserves
    uint128 public override vestingReserves;

    /// @inheritdoc IOrigamiVestingReserves
    uint128 public override futureVestingReserves;

    uint48 private constant MAX_RESERVES_VESTING_DURATION = 7 days;

    constructor(uint48 reservesVestingDuration_) {
        _setReservesVestingDuration(reservesVestingDuration_);
    }

    /// @dev The implementation may optionally allow the reserves vesting duration
    /// to be updated.
    function _setReservesVestingDuration(uint48 durationInSeconds) internal {
        if (durationInSeconds == 0) revert CommonEventsAndErrors.InvalidParam();
        if (durationInSeconds > MAX_RESERVES_VESTING_DURATION) revert CommonEventsAndErrors.InvalidParam();
        reservesVestingDuration = durationInSeconds;
        emit ReservesVestingDurationSet(durationInSeconds);
    }

    /// @inheritdoc IOrigamiVestingReserves
    function vestingStatus() external view override returns (
        uint256 currentPeriodVested,
        uint256 currentPeriodUnvested,
        uint256 futurePeriodUnvested
    ) {
        (currentPeriodVested, currentPeriodUnvested) = _vestingStatus();
        futurePeriodUnvested = futureVestingReserves;
    }

    /// @dev If the elapsed time since `lastVestingCheckpoint` has crossed into a new vesting window
    /// then start the new vesting period on total 
    function _checkpointPendingReserves(uint256 amountReinvested) internal {
        // New pending reserves is the prior `futureVestingReserves` plus the new amount reinvested
        uint128 pendingReserves = (futureVestingReserves + amountReinvested).encodeUInt128();

        // Nothing to checkpoint if no pending reserves
        if (pendingReserves == 0) return;

        // Check if current vesting period is complete
        uint48 secsSinceLastCheckpoint;
        uint48 currentTime = uint48(block.timestamp);
        unchecked {
            secsSinceLastCheckpoint = currentTime - lastVestingCheckpoint;
        }

        if (secsSinceLastCheckpoint < reservesVestingDuration) {
            // Current vesting period hasn't completed. Carry into the next period.
            futureVestingReserves = pendingReserves;
        } else {
            // Current vesting period is complete, start a new one with all accumulated reserves
            vestingReserves = pendingReserves;
            lastVestingCheckpoint = currentTime;
            futureVestingReserves = 0;
        }
    }

    /// @dev The current vested and unvested reserves
    function _vestingStatus() internal view returns (uint256 vested, uint256 unvested) {
        uint48 vestingDuration = reservesVestingDuration;
        uint48 secsSinceLastCheckpoint;
        unchecked {
            secsSinceLastCheckpoint = uint48(block.timestamp) - lastVestingCheckpoint;
        }

        // The whole amount has been accrued (vested but not yet added to `vestedReserves`) 
        // if the time since the last checkpoint has passed the vesting duration
        uint256 totalPending = vestingReserves;
        vested = (secsSinceLastCheckpoint >= vestingDuration)
            ? totalPending
            : totalPending.mulDiv(secsSinceLastCheckpoint, vestingDuration, OrigamiMath.Rounding.ROUND_DOWN);

        unchecked {
            unvested = totalPending - vested;
        }
    }

    function _totalAssets(uint256 totalStaked) internal view returns (uint256 totalManagedAssets) {
        // Total assets = staked amount - unvested rewards - any future period (yet to start vesting) reserves
        (, uint256 unvested) = _vestingStatus();
        uint256 totalUnvested = unvested + futureVestingReserves;
        // Will have more staked than what is unvested, but floor to 0 just in case
        unchecked {
            return totalStaked > totalUnvested ? totalStaked - totalUnvested : 0;
        }
    }
}
