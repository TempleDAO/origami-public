// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGOHM is IERC20 {
    function approved() external view returns (address);

    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;

    function balanceFrom(uint256 _amount) external view returns (uint256);
    function balanceTo(uint256 _amount) external view returns (uint256);
}
