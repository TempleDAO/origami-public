pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/gmx/IGmxVester.sol)

interface IGmxVester {
    function balanceOf(address user) external view returns (uint256);
    function claimable(address user) external view returns (uint256);
    function deposit(uint256 _amount) external;
    function withdraw() external;
    function claim() external returns (uint256);
    function getMaxVestableAmount(address _account) external view returns (uint256);
    function getTotalVested(address _account) external view returns (uint256);
}
