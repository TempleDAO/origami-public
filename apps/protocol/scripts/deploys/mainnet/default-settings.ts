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
        }
      },
      SPARK: {
        EMODES: {
          ETH: 1,
        }
      }
    },
}