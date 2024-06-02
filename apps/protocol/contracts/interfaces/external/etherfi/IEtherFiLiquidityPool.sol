pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/etherfi/IEtherFiLiquidityPool.sol)

interface IEtherFiLiquidityPool {
    function amountForShare(uint256 _share) external view returns (uint256);
}
