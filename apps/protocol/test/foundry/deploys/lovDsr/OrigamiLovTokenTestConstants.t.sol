pragma solidity 0.8.19;
// SPDX-License-Identifier: AGPL-3.0-or-later

library OrigamiLovTokenTestConstants {
    /**
     * lovDSR dependencies and constants
     */

    uint16 public constant LOV_DSR_MIN_DEPOSIT_FEE_BPS = 10; // 0.1%
    uint16 public constant LOV_DSR_MIN_EXIT_FEE_BPS = 50; // 0.5%
    uint24 public constant LOV_DSR_FEE_LEVERAGE_FACTOR = 15e4; // 15x
    uint48 public constant LOV_DSR_PERFORMANCE_FEE_BPS = 500; // 5%
    uint256 public constant LOV_DSR_IUSDC_BORROW_CAP = 2_000_000e18;

    /**
     * ovUSDC dependencies and constants
     */

    uint256 public constant UTILIZATION_RATIO_90 = 0.9e18; // 90%

    uint80 public constant GLOBAL_IR_AT_0_UR = 0.035e18; // 3.5%
    uint80 public constant GLOBAL_IR_AT_KINK = 0.05e18; // 5%
    uint80 public constant GLOBAL_IR_AT_100_UR = 0.07e18; // 7%

    uint80 public constant BORROWER_IR_AT_0_UR = 0.035e18; // 3.5%
    uint80 public constant BORROWER_IR_AT_KINK = 0.04e18; // 4%
    uint80 public constant BORROWER_IR_AT_100_UR = 0.045e18; // 4.5%

    uint96 public constant IDLE_STRATEGY_IR = 0.05e18; // 5%
    uint96 public constant OUSDC_EXIT_FEE_BPS = 10; // 0.1%
    uint256 public constant OUSDC_PERFORMANCE_FEE_BPS = 200; // 2%
    uint256 public constant OUSDC_CARRY_OVER_BPS = 500; // 5%
    uint128 public constant CB_DAILY_USDC_BORROW_LIMIT = 2_000_000e6;
    uint128 public constant CB_DAILY_OUSDC_EXIT_LIMIT = 2_000_000e18;
    uint256 public constant AAVE_STRATEGY_DEPOSIT_THRESHOLD = 100e6;
    uint256 public constant AAVE_STRATEGY_WITHDRAWAL_THRESHOLD = 100e6;

    uint128 public constant USER_AL_FLOOR = 1.08e18;
    uint128 public constant USER_AL_CEILING = 1.13e18;
    uint128 public constant REBALANCE_AL_FLOOR = 1.05e18;
    uint128 public constant REBALANCE_AL_CEILING = 1.15e18;

    address public constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant SDAI_ADDRESS = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address public constant ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address public constant AAVE_POOL_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant DAI_USD_ORACLE = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;

    uint96 public constant SDAI_INTEREST_RATE = 0.05e18;  // 5% APR

    uint8 public constant DAI_DECIMALS = 18; // $DAI decimals
    uint8 public constant USD_DECIMALS = 18; // $USD decimals (assume 18 for currency)
    uint8 public constant USDC_DECIMALS = 6; // $USDC decimals
    uint8 public constant IUSDC_DECIMALS = 18; // $iUSDC decimals (note this is different - debt tokens always 18dp)

    address public constant INTERNAL_USD_ADDRESS = 0x000000000000000000000000000000000000115d;

    uint128 public constant DAI_USD_STALENESS_THRESHOLD = 1 hours + 15 minutes; // It should update every hour or more. So set to 1:15hr
    uint128 public constant DAI_USD_MIN_THRESHOLD = 0.95e18;
    uint128 public constant DAI_USD_MAX_THRESHOLD = 1.05e18;
    uint256 public constant DAI_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg

    uint128 public constant USDC_USD_STALENESS_THRESHOLD = 1 days + 15 minutes; // It should update every 86400 seconds. So set to 1day 15mins
    uint128 public constant USDC_USD_MIN_THRESHOLD = 0.95e18;
    uint128 public constant USDC_USD_MAX_THRESHOLD = 1.05e18;
    uint256 public constant USDC_USD_HISTORIC_STABLE_PRICE = 1e18; // Expect it to be at 1:1 peg
}
