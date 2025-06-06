pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/kodiak/IKodiakIsland.sol)

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IKodiakV3Pool } from "contracts/interfaces/external/kodiak/IKodiakV3Pool.sol";

interface IKodiakIsland is IERC20 {
    function getUnderlyingBalances() external view returns (uint256 amount0Current, uint256 amount1Current);
    function token0() external view returns (IERC20);
    function token1() external view returns (IERC20);
    function pool() external view returns (IKodiakV3Pool);
    function lowerTick() external view returns (int24);
    function upperTick() external view returns (int24);
    function getMintAmounts(uint256 amount0Max, uint256 amount1Max) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);
}
