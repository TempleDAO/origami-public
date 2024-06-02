pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/renzo/IRenzoRestakeManager.sol)

interface IRenzoRestakeManager {
    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);
}
