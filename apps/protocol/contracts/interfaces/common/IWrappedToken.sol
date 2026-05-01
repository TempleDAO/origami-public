pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/common/IWrappedToken.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrappedToken is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}
