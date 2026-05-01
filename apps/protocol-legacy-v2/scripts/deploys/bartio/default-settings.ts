import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
  LOV_HONEY_A: {
    TOKEN_SYMBOL: "lov-HONEY-a",
    TOKEN_NAME: "Origami lov-HONEY-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  LOV_WBERA_LONG_A: {
    TOKEN_SYMBOL: "lov-WBERA-long-a",
    TOKEN_NAME: "Origami lov-WBERA-long-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  LOV_YEET_A: {
    TOKEN_SYMBOL: "lov-YEET-a",
    TOKEN_NAME: "Origami lov-YEET-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  LOV_WBTC_LONG_A: {
    TOKEN_SYMBOL: "lov-WBTC-long-a",
    TOKEN_NAME: "Origami lov-WBTC-long-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  LOV_WETH_LONG_A: {
    TOKEN_SYMBOL: "lov-WETH-long-a",
    TOKEN_NAME: "Origami lov-WETH-long-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  LOV_LOCKS_A: {
    TOKEN_SYMBOL: "lov-LOCKS-a",
    TOKEN_NAME: "Origami lov-LOCKS-a",

    MIN_DEPOSIT_FEE_BPS: 100, // 1%
    MIN_EXIT_FEE_BPS: 250, // 2.5%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 1000, // 10%

    USER_AL_FLOOR: ethers.utils.parseEther("1.1835"),        // 84.5% LTV == 6.45x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.1905"),   // 84% LTV == 6.25x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("1000000"),
  },

  VAULTS: {
    BOYCO_HONEY_A: {
      TOKEN_SYMBOL: "oboy-HONEY-a",
      TOKEN_NAME: "Origami Boyco Honey",
  
      BEX_POOL_INDEX: 36_000, // 0.5%, full width
    }
  },

}