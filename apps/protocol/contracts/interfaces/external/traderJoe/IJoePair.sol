pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/traderJoe/IJoePair.sol)

interface IJoePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    );
}
