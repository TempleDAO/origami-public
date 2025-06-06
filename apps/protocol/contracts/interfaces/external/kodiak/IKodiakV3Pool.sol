pragma solidity ^0.8.4;
// SPDX-License-Identifier: AGPL-3.0-or-later
// Origami (interfaces/external/kodiak/IKodiakV3Pool.sol)

/// @dev Kodiak is a uniswap v3 fork -- however they changed the feeProtocol from uint8 => uint32
interface IKodiakV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint32 feeProtocol,
        bool unlocked
    );
        
    function token0() external view returns (address);
    function token1() external view returns (address);
}
