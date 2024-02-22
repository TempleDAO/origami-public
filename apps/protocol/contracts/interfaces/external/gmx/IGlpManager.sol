pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGlpManager.sol)

interface IGlpManager {
    function getAumInUsdg(bool maximise) external view returns (uint256);
    function glp() external view returns (address);
    function usdg() external view returns (address);
    function vault() external view returns (address);
    function getAums() external view returns (uint256[] memory);
    function cooldownDuration() external view returns (uint256);
    function lastAddedAt(address a) external view returns (uint256);
}
