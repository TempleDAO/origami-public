pragma solidity ^0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lov_wstETH_wETH_TestConstants {
    /**
     * LovWstEth-Morpho dependencies and constants
     */

    uint16 public constant MIN_DEPOSIT_FEE_BPS = 10; // 0.1%
    uint16 public constant MIN_EXIT_FEE_BPS = 50; // 0.5%
    uint24 public constant FEE_LEVERAGE_FACTOR = 15e4; // 15x
    uint48 public constant PERFORMANCE_FEE_BPS = 500; // 5%

    uint128 public constant TARGET_AL = 1.125e18; // 88.888% LTV == 9x EE
    uint128 public constant USER_AL_FLOOR = 1.112e18; // 89.92% LTV == 9.93x EE
    uint128 public constant USER_AL_CEILING = 1.162790e18; // 86% LTV == 7.14x EE
    uint128 public constant REBALANCE_AL_FLOOR = 1.112e18; // 89.92% LTV == 9.93x EE
    uint128 public constant REBALANCE_AL_CEILING = 1.149425e18; // 87% LTV == 7.69x EE

    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant STETH_ETH_ORACLE = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    address public constant ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MORPHO_MARKET_ORACLE = 0x2a01EB9496094dA03c4E364Def50f5aD1280AD72;
    address public constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 public constant MORPHO_MARKET_LLTV = 0.945e18; // 94.5%
    uint96 public constant MAX_SAFE_LLTV = 0.9e18; // 90%

    uint8 public constant WSTETH_DECIMALS = 18; // $wstETH decimals
    uint8 public constant STETH_DECIMALS = 18; // $stETH decimals
    uint8 public constant ETH_DECIMALS = 18; // $ETH decimals

    uint128 public constant STETH_ETH_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 public constant STETH_ETH_MIN_THRESHOLD = 0.99e18;
    uint128 public constant STETH_ETH_MAX_THRESHOLD = 1.01e18;
    uint256 public constant STETH_ETH_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
}
