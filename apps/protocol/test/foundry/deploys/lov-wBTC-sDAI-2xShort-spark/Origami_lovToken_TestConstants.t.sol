pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lovToken_TestConstants {
    uint16 public constant MIN_DEPOSIT_FEE_BPS = 100; // 1%
    uint16 public constant MIN_EXIT_FEE_BPS = 100; // 1%
    uint24 public constant FEE_LEVERAGE_FACTOR = 0; // N/A
    uint48 public constant PERFORMANCE_FEE_BPS = 150; // 1.5%

    uint128 public constant TARGET_AL = 2e18;                 // 50% LTV == 2x EE
    uint128 public constant USER_AL_FLOOR = 1.6667e18;        // 60% LTV == 2.5x EE
    uint128 public constant USER_AL_CEILING = 2.5e18;         // 40% LTV == 1.67x EE
    uint128 public constant REBALANCE_AL_FLOOR = 1.8332e18;   // 54.55% LTV == 2.2x EE
    uint128 public constant REBALANCE_AL_CEILING = 2.2498e18; // 45.45% LTV == 1.8x EE

    address public constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    uint8 public constant WBTC_DECIMALS = 8;
    address public constant SDAI_ADDRESS = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    uint8 public constant SDAI_DECIMALS = 18;

    address public constant BTC_USD_ORACLE = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // chainlink
    uint128 public constant BTC_USD_STALENESS_THRESHOLD = 1 hours + 15 minutes;

    address public constant ONE_INCH_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;

    address public constant SPARK_POOL_ADDRESS_PROVIDER = 0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE;
    address public constant SPARK_POOL = 0xC13e21B648A5Ee794902342038FF3aDAB66BE987;
    uint8 public constant SPARK_EMODE_NOT_ENABLED = 0; // No emode for wBTC/sDAI market
}
