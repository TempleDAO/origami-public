// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface GMX_ITimelock {
    function buffer() external view returns (uint256);
    function signalMint(address _token, address _receiver, uint256 _amount) external;
    function processMint(address _token, address _receiver, uint256 _amount) external;
}
