pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lov_ezETH_wETH_TestConstants {
    /**
     * lov-ezETH-wETH dependencies and constants
     */

    uint16 public constant MIN_DEPOSIT_FEE_BPS = 100; // 1%
    uint16 public constant MIN_EXIT_FEE_BPS = 100; // 1%
    uint24 public constant FEE_LEVERAGE_FACTOR = 7e4; // 7x
    uint48 public constant PERFORMANCE_FEE_BPS = 1000; // 10%

    uint128 public constant TARGET_AL = 1.25e18;               // 80% LTV == 5x EE
    uint128 public constant USER_AL_FLOOR = 1.1977e18;         // 83.5% LTV == 6.06x EE
    uint128 public constant USER_AL_CEILING = 1.4286e18;       // 70% LTV == 3.33x EE
    uint128 public constant REBALANCE_AL_FLOOR = 1.2270e18;    // 81.5% LTV == 5.41x EE
    uint128 public constant REBALANCE_AL_CEILING = 1.3334e18;  // 75% LTV == 4x EE

    address public constant EZETH_ADDRESS = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant RENZO_RESTAKE_MANAGER = 0x74a09653A083691711cF8215a6ab074BB4e99ef5;
    address public constant REDSTONE_EZETH_ETH_ORACLE = 0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696;

    address public constant ONE_INCH_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MORPHO_MARKET_ORACLE = 0x61025e2B0122ac8bE4e37365A4003d87ad888Cc3;
    address public constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 public constant MORPHO_MARKET_LLTV = 0.86e18; // 86%
    uint96 public constant MAX_SAFE_LLTV = 0.835e18; // 83.5%

    uint8 public constant EZETH_DECIMALS = 18;
    uint8 public constant WETH_DECIMALS = 18;

    uint128 public constant EZETH_ETH_STALENESS_THRESHOLD = 12 hours + 1 minutes;  
    uint128 public constant EZETH_ETH_MAX_REL_DIFF_THRESHOLD_BPS = 30; // 0.3%
}
