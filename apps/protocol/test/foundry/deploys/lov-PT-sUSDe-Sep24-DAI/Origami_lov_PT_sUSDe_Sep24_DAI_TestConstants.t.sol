pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library Origami_lov_PT_sUSDe_Sep24_DAI_TestConstants {
    /**
     * dependencies and constants
     */

    uint16 public constant MIN_DEPOSIT_FEE_BPS = 0; // 0%
    uint16 public constant MIN_EXIT_FEE_BPS = 300; // 3%
    uint24 public constant FEE_LEVERAGE_FACTOR = 10e4; // 15x
    uint48 public constant PERFORMANCE_FEE_BPS = 500; // 5%

    // TARGET_AL is in terms of the market A/L
    uint128 public constant TARGET_LTV = 0.8e18;

    // These are in terms of Morpho's LTV
    uint128 public constant USER_AL_FLOOR = 1.1835e18;
    uint128 public constant USER_AL_CEILING = 1.4286e18;
    uint128 public constant REBALANCE_AL_FLOOR = 1.1905e18;
    uint128 public constant REBALANCE_AL_CEILING = 1.3334e18;

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDE_ADDRESS = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    address public constant PT_SUSDE_SEP24_ADDRESS = 0x6c9f097e044506712B58EAC670c9a5fd4BCceF13;
    address public constant PT_SUSDE_SEP24_MARKET = 0xd1D7D99764f8a52Aff007b7831cc02748b2013b5;

    address public constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address public constant PENDLE_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
    uint32 public constant PENDLE_TWAP_DURATION = 900;

    address public constant USDE_USD_ORACLE = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MORPHO_MARKET_ORACLE = 0xaE4750d0813B5E37A51f7629beedd72AF1f9cA35; // 1:1
    address public constant MORPHO_MARKET_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint96 public constant MORPHO_MARKET_LLTV = 0.86e18;
    uint96 public constant MAX_SAFE_LLTV = 0.845e18;

    uint8 public constant PT_SUSDE_SEP24_DECIMALS = 18;
    uint8 public constant USDE_DECIMALS = 18;
    uint8 public constant DAI_DECIMALS = 18;

    uint128 public constant USDE_USD_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 public constant USDE_USD_MIN_THRESHOLD = 0.995e18;
    uint128 public constant USDE_USD_MAX_THRESHOLD = 1.005e18;
    uint256 public constant USDE_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
}
