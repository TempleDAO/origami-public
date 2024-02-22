pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGmxReader.sol)

interface IGmxReader {
    function getTokenBalancesWithSupplies(address _account, address[] memory _tokens) external view returns (uint256[] memory);
}
