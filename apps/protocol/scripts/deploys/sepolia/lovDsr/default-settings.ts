import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    /**
     * lovDSR dependencies and constants
     */
    LOV_DSR: {
      LOV_DSR_MIN_DEPOSIT_FEE_BPS: 0, // 0%
      LOV_DSR_MIN_EXIT_FEE_BPS: 50, // 0.5%
      LOV_DSR_FEE_LEVERAGE_FACTOR: 15, // targetting ~EE of the REBALANCE_AL_FLOOR
      LOV_DSR_REDEEMABLE_RESERVES_BUFFER: 0,
      LOV_DSR_PERFORMANCE_FEE_BPS: 500, // 5%
      LOV_DSR_IUSDC_BORROW_CAP: ethers.utils.parseEther((2_000_000).toString()), // 2mm lovDSR/day

      USER_AL_FLOOR: ethers.utils.parseEther("1.06"),        // 94.34% LTV, 17.67x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.14"),      // 87.72% LTV, 8.14x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.08"),   // 92.59% LTV, 13.5x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.12"), // 89.29% LTV, 9.33x EE

      UTILIZATION_RATIO_KINK: ethers.utils.parseEther("0.9"), // 90%
      BORROWER_IR_AT_0_UR: ethers.utils.parseEther("0.04"), // 4%
      BORROWER_IR_AT_KINK: ethers.utils.parseEther("0.04"), // 4%
      BORROWER_IR_AT_100_UR: ethers.utils.parseEther("0.045"), // 4.5%
    },

    /**
     * ovUSDC dependencies and constants
     */
    OV_USDC: {
      UTILIZATION_RATIO_KINK: ethers.utils.parseEther("0.9"), // 90%

      GLOBAL_IR_AT_0_UR: ethers.utils.parseEther("0.04"), // 4.5%
      GLOBAL_IR_AT_KINK: ethers.utils.parseEther("0.045"), // 4%
      GLOBAL_IR_AT_100_UR: ethers.utils.parseEther("0.06"), // 6%

      IDLE_STRATEGY_IR: ethers.utils.parseEther("0.05"), // 5%
      OUSDC_PERFORMANCE_FEE_BPS: 200, // 2%
      OUSDC_CARRY_OVER_BPS: 500, // 5%
      REWARDS_VEST_SECONDS: 2 * 86_400, // 2 days
      CB_DAILY_USDC_BORROW_LIMIT: ethers.utils.parseUnits((2_000_000).toString(), 6), // 2mm USDC/day
      CB_DAILY_OUSDC_EXIT_LIMIT: ethers.utils.parseEther((2_000_000).toString()), // 2mm oUSDC/day
      AAVE_STRATEGY_DEPOSIT_THRESHOLD: ethers.utils.parseUnits("100", 6), // 100 USDC in idle strategy
      AAVE_STRATEGY_WITHDRAWAL_THRESHOLD: ethers.utils.parseUnits("100", 6), // 100 USDC buffer in idle strategy
    },
    ORACLES: {
      DAI_USD: {
        STALENESS_THRESHOLD: 87300, // 1 days + 15 minutes
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.01"), 
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      IUSDC_USD: {
        STALENESS_THRESHOLD: 87300, // 1 days + 15 minutes
        MIN_THRESHOLD: ethers.utils.parseEther("0.99"), 
        MAX_THRESHOLD: ethers.utils.parseEther("1.01"), 
        HISTORIC_PRICE: ethers.utils.parseEther("1.0"), // Expect to be at 1:1 peg
        BASE_DECIMALS: 18,
        QUOTE_DECIMALS: 18,
      },
      // Doesn't matter what this is as long as it's consistent - only used internally
      // 115d ==> USD
      INTERNAL_USD_ADDRESS: "0x000000000000000000000000000000000000115d",
    },
    EXTERNAL: {
      SDAI_INTEREST_RATE: ethers.utils.parseEther("0.05"),  // 5% APR, testnet only
    },
}