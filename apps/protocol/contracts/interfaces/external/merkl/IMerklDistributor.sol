pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/merkl/IMerklDistributor.sol)

interface IMerklDistributor {
    /// @notice Toggles whitelisting for a given user and a given operator
    /// @dev When an operator is whitelisted for a user, the operator can claim rewards on behalf of the user
    function toggleOperator(address user, address operator) external;

    /// @notice Sets a recipient for a user claiming rewards for a token
    /// @dev This is an optional functionality and if the `recipient` is set to the zero address, then
    /// the user will still accrue all rewards to its address
    /// @dev Users may still specify a different recipient when they claim token rewards with the
    /// `claimWithRecipient` function
    function setClaimRecipient(address recipient, address token) external;
}
