pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/kodiak/IKodiakIslandRouter.sol)

interface IKodiakIslandRouter {
    function addLiquidity(
        address island,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 amountSharesMin,
        address receiver
    ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount);
}