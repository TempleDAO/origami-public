import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    /**
     * lov-sUSDe-5x dependencies and constants
     */
    LOV_SUSDE_5X: {
      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 50, // 0.5%
      FEE_LEVERAGE_FACTOR: 8e4, // targetting ~EE of the REBALANCE_AL_FLOOR
      REDEEMABLE_RESERVES_BUFFER: 0,
      PERFORMANCE_FEE_BPS: 500, // 5%

      USER_AL_FLOOR: ethers.utils.parseEther("1.14285714285714"),        // 87.5% LTV == 8x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.42857142857143"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.17647058823529"),   // 85% LTV == 6.66x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.33333333333333"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.915"), // 91.5% LTV
        SAFE_LTV: ethers.utils.parseEther("0.89"), // 89% LTV
      },

      INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("10000000"),
    },

    ORACLES: {
      USDE_DAI: {
        STALENESS_THRESHOLD: 87300, // 1 days + 15 minutes
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
    },
    EXTERNAL: {
      SUSDE_INTEREST_RATE: ethers.utils.parseEther("0.3"),  // 30% APR, testnet only
    },
}