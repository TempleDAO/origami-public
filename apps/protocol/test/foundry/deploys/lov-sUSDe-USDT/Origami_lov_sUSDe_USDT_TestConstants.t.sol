pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lov_sUSDe_USDT_TestConstants {
    /**
     * Lov-sUSDe-USDT dependencies and constants
     */

    uint16 public constant MIN_DEPOSIT_FEE_BPS = 10; // 0.1%
    uint16 public constant MIN_EXIT_FEE_BPS = 50; // 0.5%
    uint24 public constant FEE_LEVERAGE_FACTOR = 15e4; // 15x
    uint48 public constant PERFORMANCE_FEE_BPS = 500; // 5%

    uint128 public constant TARGET_AL = 1.3333e18; // 75% LTV == 4x EE
    uint128 public constant USER_AL_FLOOR = 1.28571e18; // 77.77% LTV == 4.5x EE
    uint128 public constant USER_AL_CEILING = 1.4e18; // 71.42857% LTV == 3.5x EE
    uint128 public constant REBALANCE_AL_FLOOR = 1.28571e18; // 77.77% LTV == 4.5x EE
    uint128 public constant REBALANCE_AL_CEILING = 1.4e18; // 71.42857% LTV == 3.5x EE

    address public constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant SUSDE_ADDRESS = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDE_ADDRESS = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    address public constant USDE_USD_ORACLE = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

    address public constant ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MORPHO_MARKET_ORACLE = 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99;
    address public constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 public constant MORPHO_MARKET_LLTV = 0.915e18; // 91.5%
    uint96 public constant MAX_SAFE_LLTV = 0.89e18; // 89%

    uint8 public constant SUSDE_DECIMALS = 18; // $sUSDe decimals
    uint8 public constant USDE_DECIMALS = 18; // $USDe decimals
    uint8 public constant USDT_DECIMALS = 6; // $USDT decimals

    uint128 public constant USDE_USD_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 public constant USDE_USD_MIN_THRESHOLD = 0.995e18;
    uint128 public constant USDE_USD_MAX_THRESHOLD = 1.005e18;
    uint256 public constant USDE_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
}
