pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (investments/util/OrigamiManagerPausable.sol)

import { CommonEventsAndErrors } from "contracts/libraries/CommonEventsAndErrors.sol";
import { OrigamiElevatedAccess } from "contracts/common/access/OrigamiElevatedAccess.sol";
import { IOrigamiManagerPausable } from "contracts/interfaces/investments/util/IOrigamiManagerPausable.sol";

/**
 * @title A mixin to add pause/unpause for Origami manager contracts
 */
abstract contract OrigamiManagerPausable is IOrigamiManagerPausable, OrigamiElevatedAccess {
    /**
     * @notice A set of accounts which are allowed to pause deposits/withdrawals immediately
     * under emergency
     */
    mapping(address account => bool canPause) public pausers;

    /**
     * @notice The current paused/unpaused state of deposits/exits.
     */
    Paused internal _paused;

    /**
     * @notice Pause/unpause deposits or exits
     * @dev Can only be called by allowed pausers.
     */
    function setPaused(Paused calldata updatedPaused) external {
        if (!pausers[msg.sender]) revert CommonEventsAndErrors.InvalidAccess();
        emit PausedSet(updatedPaused);
        _paused = updatedPaused;
    }

    /**
     * @notice Allow/Deny an account to pause/unpause deposits or exits
     */
    function setPauser(address account, bool canPause) external onlyElevatedAccess {
        pausers[account] = canPause;
        emit PauserSet(account, canPause);
    }

    /**
     * @notice Check if given account can pause deposits/exits
     */
    function isPauser(address account) external view override returns (bool canPause) {
        canPause = pausers[account];
    }
}
