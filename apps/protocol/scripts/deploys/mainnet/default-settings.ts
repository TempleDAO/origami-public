import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    LOV_SUSDE_A: {
      TOKEN_SYMBOL: "lov-sUSDe-a",
      TOKEN_NAME: "Origami lov-sUSDe-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 250, // 2.5%
      FEE_LEVERAGE_FACTOR: 7e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.845"),       // 84.5% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // No deposits allowed to start
    },

    LOV_SUSDE_B: {
      TOKEN_SYMBOL: "lov-sUSDe-b",
      TOKEN_NAME: "Origami lov-sUSDe-b",

      MIN_DEPOSIT_FEE_BPS: 100, // 1%
      MIN_EXIT_FEE_BPS: 350, // 3.5%
      FEE_LEVERAGE_FACTOR: 10e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1112"),        // 90% LTV == 10x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.3334"),      // 75% LTV == 4x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1236"),   // 89% LTV == 9.09x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.25"),   // 80% LTV == 5x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.915"), // 91.5% LTV
        SAFE_LTV: ethers.utils.parseEther("0.9"),          // 90% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10000"), // 10k allowed to start
    },

    LOV_USDE_A: {
      TOKEN_SYMBOL: "lov-USDe-a",
      TOKEN_NAME: "Origami lov-USDe-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 7e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1977"),        // 83.5% LTV == 6.06x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.2122"),   // 82.5% LTV == 5.71x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.835"),       // 83.5% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"), // 1mm
    },

    LOV_USDE_B: {
      TOKEN_SYMBOL: "lov-USDe-b",
      TOKEN_NAME: "Origami lov-USDe-b",

      MIN_DEPOSIT_FEE_BPS: 150, // 1.5%
      MIN_EXIT_FEE_BPS: 150, // 1.5%
      FEE_LEVERAGE_FACTOR: 10e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1236"),        // 89% LTV == 9.09x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.3334"),      // 75% LTV == 4x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1364"),   // 88% LTV == 8.33x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.25"),   // 80% LTV == 5x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.915"), // 91.5% LTV
        SAFE_LTV: ethers.utils.parseEther("0.89"),         // 89% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10000"), // 10k allowed to start
    },

    LOV_WEETH_A: {
      TOKEN_SYMBOL: "lov-weETH-a",
      TOKEN_NAME: "Origami lov-weETH-a",

      MIN_DEPOSIT_FEE_BPS: 100, // 1%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 6e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.25"),          // 80% LTV == 5x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.5385"),      // 65% LTV == 2.86x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.2659"),   // 79% LTV == 4.76x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.4286"), // 70% LTV == 3.33x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.80"),        // 80% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10"), // Small initial supply
    },

    LOV_EZETH_A: {
      TOKEN_SYMBOL: "lov-ezETH-a",
      TOKEN_NAME: "Origami lov-ezETH-a",

      MIN_DEPOSIT_FEE_BPS: 100, // 1%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 7e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1977"),        // 83.5% LTV == 6.06x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.227"),    // 81.5% LTV == 5.41x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.835"),       // 83.5% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10"), // Small initial supply
    },

    LOV_WSTETH_A: {
      TOKEN_SYMBOL: "lov-wstETH-a",
      TOKEN_NAME: "Origami lov-wstETH-a",

      MIN_DEPOSIT_FEE_BPS: 100, // 1%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 13e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 200, // 2%

      USER_AL_FLOOR: ethers.utils.parseEther("1.087"),         // 92% LTV == 12.5x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.1765"),      // 85% LTV == 6.66x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.0929"),   // 91.5% LTV == 11.76x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.1364"), // 88% LTV == 8.33x EE

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10"), // Small initial supply
    },

    LOV_WSTETH_B: {
      TOKEN_SYMBOL: "lov-wstETH-b",
      TOKEN_NAME: "Origami lov-wstETH-b",

      MIN_DEPOSIT_FEE_BPS: 150, // 1%
      MIN_EXIT_FEE_BPS: 150, // 1%
      FEE_LEVERAGE_FACTOR: 16e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 200, // 2%

      USER_AL_FLOOR: ethers.utils.parseEther("1.0696"),        // 93.5% LTV == 15.38x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.25"),        // 80% LTV == 5x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.0753"),   // 93% LTV == 14.28x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.1236"), // 89% LTV == 9.09x EE

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10"), // Small initial supply
    },

    LOV_WOETH_A: {
      TOKEN_SYMBOL: "lov-woETH-a",
      TOKEN_NAME: "Origami lov-woETH-a",

      MIN_DEPOSIT_FEE_BPS: 100, // 1%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 7e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 200, // 2%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1905"),        // 84% LTV == 6.25x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.5385"),      // 65% LTV == 2.86x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.2196"),   // 82% LTV == 5.55x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.4286"), // 70% LTV == 3.33x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.85"),        // 85% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("50"),
    },

    LOV_WETH_DAI_LONG_A: {
      TOKEN_SYMBOL: "lov-wETH-DAI-long-a",
      TOKEN_NAME: "Origami lov-wETH-DAI-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.6667"),         // 60% LTV
      USER_AL_CEILING: ethers.utils.parseEther("2.5"),          // 40% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.8332"),    // 54.55% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("2.2498"),  // 44.45% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_WETH_SDAI_SHORT_A: {
      TOKEN_SYMBOL: "lov-wETH-sDAI-short-a",
      TOKEN_NAME: "Origami lov-wETH-sDAI-short-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.6667"),           // 60% LTV
      USER_AL_CEILING: ethers.utils.parseEther("2.5"),            // 40% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.8332"),      // 54.55% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("2.2498"),    // 44.45% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_WBTC_DAI_LONG_A: {
      TOKEN_SYMBOL: "lov-wBTC-DAI-long-a",
      TOKEN_NAME: "Origami lov-wBTC-DAI-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.6667"),         // 60% LTV
      USER_AL_CEILING: ethers.utils.parseEther("2.5"),          // 40% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.8332"),    // 54.55% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("2.2498"),  // 44.45% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_WBTC_SDAI_SHORT_A: {
      TOKEN_SYMBOL: "lov-wBTC-sDAI-short-a",
      TOKEN_NAME: "Origami lov-wBTC-sDAI-short-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.6667"),     // 60% LTV
      USER_AL_CEILING: ethers.utils.parseEther("2.5"),      // 40% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.8332"),   // 54.55% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("2.2498"), // 44.45% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_WETH_WBTC_LONG_A: {
      TOKEN_SYMBOL: "lov-wETH-wBTC-long-a",
      TOKEN_NAME: "Origami lov-wETH-wBTC-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1.0%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.3334"),        // 75% LTV
      USER_AL_CEILING: ethers.utils.parseEther("1.8182"),      // 55% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.3987"),   // 71.50% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.6667"), // 60.00% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_WETH_WBTC_SHORT_A: {
      TOKEN_SYMBOL: "lov-wETH-wBTC-short-a",
      TOKEN_NAME: "Origami lov-wETH-wBTC-short-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1.0%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.4286"),   // 70% LTV
      USER_AL_CEILING: ethers.utils.parseEther("2"),      // 50% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.5385"),   // 65% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.8182"), // 55% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_PT_SUSDE_OCT24_A: {
      TOKEN_SYMBOL: "lov-PT-sUSDe-Oct2024-a",
      TOKEN_NAME: "Origami lov-PT-sUSDe-Oct2024-a",

      MIN_DEPOSIT_FEE_BPS: 0,    // 0%
      MIN_EXIT_FEE_BPS: 300,     // 3%
      FEE_LEVERAGE_FACTOR: 8e4,  // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 500,  // 5%

      // These are in terms of the Morpho LTV
      // where it assumes PT == DAI (since that's what it can redeem for at maturity)
      USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),         // 84.5% Market LTV == 6.45x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),       // 70% Market LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),    // 84% Market LTV == 6.25x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"),  // 75% Market LTV == 4x EE

      MORPHO_BORROW_LEND: {
        // Also need to be in terms of the Morpho LTV
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"),  // 86% Morpho LTV. 
        SAFE_LTV: ethers.utils.parseEther("0.845"),        // 84.5% Morpho LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small deposits allowed at start
    },

    LOV_PT_SUSDE_MAR_2025_A: {
      TOKEN_SYMBOL: "lov-PT-sUSDe-Mar2025-a",
      TOKEN_NAME: "Origami lov-PT-sUSDe-Mar2025-a",

      MIN_DEPOSIT_FEE_BPS: 0,    // 0%
      MIN_EXIT_FEE_BPS: 200,     // 2%
      FEE_LEVERAGE_FACTOR: 10e4, // targeting ~EE (ceiling) of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 200,  // 2%

      // These are in terms of the Morpho LTV
      // marketAL = morphoAL
      //     * PT-sUSDe-Oct24/USDe [pendle twap] * USDe/DAI [redstone]
      //     / discount factor oracle
      USER_AL_FLOOR: ethers.utils.parseEther("1.1236"),         // 89% Market LTV == 9.09x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),       // 70% Market LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1429"),    // 87.5% Market LTV == 8x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"),  // 75% Market LTV == 4x EE

      MORPHO_BORROW_LEND: {
        // Also need to be in terms of the Morpho LTV
        LIQUIDATION_LTV: ethers.utils.parseEther("0.915"),  // 91.5% Morpho LTV. 
        SAFE_LTV: ethers.utils.parseEther("0.9"),           // 90% Morpho LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small deposits allowed at start
    },

    LOV_MKR_DAI_LONG_A: {
      TOKEN_SYMBOL: "lov-MKR-DAI-long-a",
      TOKEN_NAME: "Origami lov-MKR-DAI-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("2"),         // 50% LTV
      USER_AL_CEILING: ethers.utils.parseEther("5"),       // 20% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("2.5"),  // 40% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("4"),  // 25% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_AAVE_USDC_LONG_A: {
      TOKEN_SYMBOL: "lov-AAVE-USDC-long-a",
      TOKEN_NAME: "Origami lov-AAVE-USDC-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("2"),         // 50% LTV
      USER_AL_CEILING: ethers.utils.parseEther("5"),       // 20% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("2.5"),  // 40% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("4"),  // 25% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_SDAI_A: {
      TOKEN_SYMBOL: "lov-sDAI-a",
      TOKEN_NAME: "Origami lov-sDAI-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 0, // 0%
      AUM_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.087"),         // 92% LTV
      USER_AL_CEILING: ethers.utils.parseEther("1.1765"),      // 85% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.0929"),   // 91.5% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.1364"), // 88% LTV

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.965"), // 96.5% LTV
        SAFE_LTV: ethers.utils.parseEther("0.94"),         // 94% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    LOV_USD0pp_A: {
      TOKEN_SYMBOL: "lov-USD0++-a",
      TOKEN_NAME: "Origami lov-USD0++-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 400, // 4%
      FEE_LEVERAGE_FACTOR: 7e4, // targeting ~EE of the REBALANCE_AL_FLOOR
      PERFORMANCE_FEE_BPS: 500, // 5%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.845"),       // 84.5% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // No deposits allowed to start
    },

    LOV_RSWETH_A: {
      TOKEN_SYMBOL: "lov-rswETH-a",
      TOKEN_NAME: "Origami lov-rswETH-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      AUM_FEE_BPS: 200, // 2%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.087"),         // 92% LTV
      USER_AL_CEILING: ethers.utils.parseEther("1.1765"),      // 85% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.0929"),   // 91.5% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.1364"), // 88% LTV

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.945"), // 94.5% LTV
        SAFE_LTV: ethers.utils.parseEther("0.92"),         // 92% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("2"), // Small initial supply
    },

    LOV_PT_EBTC_DEC24_A: {
      TOKEN_SYMBOL: "lov-PT-eBTC-Dec2024-a",
      TOKEN_NAME: "Origami lov-PT-eBTC-Dec2024-a",

      MIN_DEPOSIT_FEE_BPS: 0,    // 0%
      MIN_EXIT_FEE_BPS: 175,     // 1.75%
      FEE_LEVERAGE_FACTOR: 0,    // N/A
      PERFORMANCE_FEE_BPS: 200,  // 2%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1112"),         // 90% Market LTV == 10x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),       // 70% Market LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1236"),    // 89% Market LTV == 9.09x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"),  // 75% Market LTV == 4x EE

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small deposits allowed at start
    },

    LOV_PT_CORN_LBTC_DEC24_A: {
      TOKEN_SYMBOL: "lov-PT-cornLBTC-Dec2024-a",
      TOKEN_NAME: "Origami lov-PT-cornLBTC-Dec2024-a",

      MIN_DEPOSIT_FEE_BPS: 0,    // 0%
      MIN_EXIT_FEE_BPS: 175,     // 1.75%
      FEE_LEVERAGE_FACTOR: 0,    // N/A
      PERFORMANCE_FEE_BPS: 200,  // 2%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1112"),         // 90% Market LTV == 10x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),       // 70% Market LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1236"),    // 89% Market LTV == 9.09x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"),  // 75% Market LTV == 4x EE

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small deposits allowed at start
    },
    
    LOV_WETH_CBBTC_LONG_A: {
      TOKEN_SYMBOL: "lov-WETH-CBBTC-long-a",
      TOKEN_NAME: "Origami lov-WETH-CBBTC-long-a",

      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      PERFORMANCE_FEE_BPS: 100, // 1.0%
      FEE_LEVERAGE_FACTOR: 0, // N/A

      USER_AL_FLOOR: ethers.utils.parseEther("1.3334"),        // 75% LTV
      USER_AL_CEILING: ethers.utils.parseEther("1.8182"),      // 55% LTV

      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.3987"),   // 71.50% LTV
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.6667"), // 60.00% LTV

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"), // Small initial supply
    },

    VAULTS: {
      SUSDSpS: {
        TOKEN_SYMBOL: "sUSDS+s",
        TOKEN_NAME: "Origami sUSDS + Sky Farms",
        SWITCH_FARM_COOLDOWN_SECS: 86_400,
        PERFORMANCE_FEE_FOR_CALLER_BPS: 100,
        PERFORMANCE_FEE_FOR_ORIGAMI_BPS: 400,
        
        STAKING_FARMS: {
          USDS_SKY: {
            REFERRAL_CODE: 0,
          },
        },

        SEED_DEPOSIT_SIZE: ethers.utils.parseUnits("995.400217986347109878", 18), // USDS
        MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256,

        COW_SWAPPERS: {
          // Sell Exactly 10k SKY and Buy a min of 500 USDS
          SKY_TO_USDS_EXACT_SELL_AMOUNT: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("10000", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("500", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: false,
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          }
        }
      }
    },

    ORACLES: {
      USDE_DAI: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.995"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.005"), 
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      SUSDE_DAI: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      WEETH_WETH: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
        MAX_RELATIVE_TOLERANCE_BPS: 30, // weETH redemption price vs oracle tolerance
      },
      EZETH_WETH: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
        MAX_RELATIVE_TOLERANCE_BPS: 30, // ezETH redemption price vs oracle tolerance
      },
      STETH_WETH: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.997"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.003"), 
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      WSTETH_WETH: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      WOETH_WETH: {
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      DAI_USD: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"),
        MAX_THRESHOLD: ethers.utils.parseEther("999"),
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
      },
      PT_SUSDE_OCT24_DAI: {
        TWAP_DURATION_SECS: 900, 
      },
      PT_SUSDE_MAR_2025_SUSDE: {
        TWAP_DURATION_SECS: 3600,
      },
      PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.9"),
        MAX_THRESHOLD: ethers.utils.parseEther("1"),
      },
      USD0pp_USD0: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"), 
        MAX_THRESHOLD: ethers.utils.parseEther("100"),  // No revert on upper bound
      },
      USD0_USDC: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.01"),
      },
      USD0pp_USDC: {
        FIXED_PRICE: ethers.utils.parseEther("1")
      },
      USDC_USD: {
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"),
        MAX_THRESHOLD: ethers.utils.parseEther("999"),
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
      },
      PT_EBTC_DEC24_EBTC: {
        TWAP_DURATION_SECS: 30*60, // 30min twap
      },
      PT_CORN_LBTC_DEC24_LBTC: {
        TWAP_DURATION_SECS: 30*60, // 30min twap
      },
    },

    EXTERNAL: {
      REDSTONE: {
        USDE_USD_ORACLE: {
          STALENESS_THRESHOLD: 86400 + 300 // 1 days + 5 minutes
        },
        SUSDE_USD_ORACLE: {
          STALENESS_THRESHOLD: 86400 + 300 // 1 days + 5 minutes
        },
        WEETH_WETH_ORACLE: {
          STALENESS_THRESHOLD: 86400 + 300 // 1 days + 5 minutes
        },
        WEETH_USD_ORACLE: {
          STALENESS_THRESHOLD: 21600 + 300 // 6 hours + 5 minutes
        },
        EZETH_WETH_ORACLE: {
          STALENESS_THRESHOLD: 43200 + 300 // 12 hrs + 5 minutes
        },
      },
      CHAINLINK: {
        ETH_USD_ORACLE: {
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        STETH_ETH_ORACLE: {
          STALENESS_THRESHOLD: 86400 + 300 // 1 days + 5 minutes
        },
        BTC_USD_ORACLE: {
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        ETH_BTC_ORACLE: {
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        DAI_USD_ORACLE: {
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        MKR_USD_ORACLE: {
          // https://data.chain.link/feeds/ethereum/mainnet/mkr-usd
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        AAVE_USD_ORACLE: {
          // https://data.chain.link/feeds/ethereum/mainnet/aave-usd
          STALENESS_THRESHOLD: 3600 + 300 // 1 hr + 5 minutes
        },
        USDC_USD_ORACLE: {
          // https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
          STALENESS_THRESHOLD: 86400 + 300 // 1 hr + 5 minutes
        },
      },
      CHRONICLE: {
        USDS_USD_ORACLE: {
          // https://chroniclelabs.org/dashboard/oracle/USDS/USD?blockchain=ETH
          STALENESS_THRESHOLD: 43200 + 300 // 12 hours + 5 minutes
        },
        SKY_USD_ORACLE: {
          // https://chroniclelabs.org/dashboard/oracle/SKY/USD?blockchain=ETH
          STALENESS_THRESHOLD: 43200 + 300 // 12 hours + 5 minutes
        },
      },
      SPARK: {
        EMODES: {
          DEFAULT: 0,
          ETH: 1,
        }
      },
      AAVE: {
        EMODES: {
          DEFAULT: 0,
          ETH: 1,
        }
      },
      ZEROLEND: {
        EMODES: {
          DEFAULT: 0, // ZEROLEND has no other EMODES
        }
      },
    },

    MAINNET_TEST: {
      SWAPPERS: {
        COW_SWAPPER_1: {
          SDAI_SUSDE: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("100000", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("100000", 18), // never buy at a discount
            PARTIALLY_FILLABLE: true,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: false,
            LIMIT_PRICE_PREMIUM_BPS: 30,
            VERIFY_SLIPPAGE_BPS: 3,
            ROUND_DOWN_DIVISOR: ethers.utils.parseUnits("5", 18),
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          },
        },

        COW_SWAPPER_2: {
          // Sell exactly 100 sDAI and Buy a min of 90 sUSDe
          SDAI_SUSDE_EXACT_SELL_AMOUNT: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("100", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("90", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: false, // We want it to be exact not based off balance
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          },

          // Sell a max of 1000 sDAI and Buy a min amount of 100 sUSDe
          SDAI_SUSDE_MIN_BUY_AMOUNT: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("1000", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("100", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: true, // will use the contract balance of sDAI
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          },

          // Sell exactly 100 sUSDe and Buy a min of 90 sDAI
          SUSDE_SDAI_EXACT_SELL_AMOUNT: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("100", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("90", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: false, // We want it to be exact not based off balance
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          },

          // Sell a max of 1000 sUSDe and Buy a min amount of 100 sDAI
          SUSDE_SDAI_MIN_BUY_AMOUNT: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("1000", 18),
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("100", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: true, // will use the contract balance of sDAI
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          }
        }
      },
    },

}