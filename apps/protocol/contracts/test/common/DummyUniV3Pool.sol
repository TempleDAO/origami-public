pragma solidity 0.8.17;
// SPDX-License-Identifier: AGPL-3.0-or-later

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3Pool} from "../../interfaces/external/uniswap/IUniswapV3Pool.sol";

contract DummyUniV3Pool is IUniswapV3Pool {
    uint160 public _sqrtPriceX96;
    address public immutable _token0;
    address public immutable _token1;

    event PriceSet(uint256 price, uint160 sqrtPriceX96);

    constructor(uint160 price, address __token0, address __token1) {
        setPrice(price);
        _token0 = __token0;
        _token1 = __token1;
    }

    /// @dev expected in 1e30 precision
    function setPrice(uint256 price) public {
        _sqrtPriceX96 = uint160(Math.sqrt(price) * (1 << 96) / 1e15);
        emit PriceSet(price, _sqrtPriceX96);
    }

    function slot0() external override view returns (
        uint160 /*_sqrtPriceX96*/,
        int24 /*_tick*/,
        uint16 /*_observationIndex*/,
        uint16 /*_observationCardinality*/,
        uint16 /*_observationCardinalityNext*/,
        uint8 /*_feeProtocol*/,
        bool /*_unlocked*/
    ) {
       return (_sqrtPriceX96, 0, 0, 0, 0, 0, true);
    }
        
    function token0() external override view returns (address) {
        return _token0;
    }

    function token1() external override view returns (address) {
        return _token1;
    }
}
