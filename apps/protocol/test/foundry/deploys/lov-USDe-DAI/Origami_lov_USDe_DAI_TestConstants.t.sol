pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lov_USDe_DAI_TestConstants {
    /**
     * Lov-USDe-DAI dependencies and constants
     */

    uint16 public constant MIN_DEPOSIT_FEE_BPS = 0; // 0%
    uint16 public constant MIN_EXIT_FEE_BPS = 100; // 1%
    uint24 public constant FEE_LEVERAGE_FACTOR = 7e4; // 7x
    uint48 public constant PERFORMANCE_FEE_BPS = 1000; // 10%

    uint128 public constant TARGET_AL = 1.25e18;               // 80% LTV == 5x EE
    uint128 public constant USER_AL_FLOOR = 1.1977e18;         // 83.5% LTV == 6.06x EE
    uint128 public constant USER_AL_CEILING = 1.4286e18;       // 70% LTV == 3.33x EE
    uint128 public constant REBALANCE_AL_FLOOR = 1.2049e18;    // 83% LTV == 5.88x EE
    uint128 public constant REBALANCE_AL_CEILING = 1.3334e18;  // 75% LTV == 4x EE

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDE_ADDRESS = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    address public constant USDE_USD_ORACLE = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

    address public constant ONE_INCH_ROUTER = 0x111111125421cA6dc452d289314280a0f8842A65;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MORPHO_MARKET_ORACLE = 0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35;
    address public constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 public constant MORPHO_MARKET_LLTV = 0.86e18; // 86%
    uint96 public constant MAX_SAFE_LLTV = 0.835e18; // 83.5%

    uint8 public constant USDE_DECIMALS = 18; // $USDe decimals
    uint8 public constant DAI_DECIMALS = 18; // $DAI decimals

    uint128 public constant USDE_USD_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 public constant USDE_USD_MIN_THRESHOLD = 0.995e18;
    uint128 public constant USDE_USD_MAX_THRESHOLD = 1.005e18;
    uint256 public constant USDE_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
}
