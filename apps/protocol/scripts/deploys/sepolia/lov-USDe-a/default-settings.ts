import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    /**
     * lov-USDe dependencies and constants
     */
    LOV_USDE: {
      MIN_DEPOSIT_FEE_BPS: 0, // 0%
      MIN_EXIT_FEE_BPS: 100, // 1%
      FEE_LEVERAGE_FACTOR: 7e4, // targetting ~EE of the REBALANCE_AL_FLOOR
      REDEEMABLE_RESERVES_BUFFER: 0,
      PERFORMANCE_FEE_BPS: 1000, // 10%

      USER_AL_FLOOR: ethers.utils.parseEther("1.1977"),        // 83.5% LTV == 6.06x EE
      USER_AL_CEILING: ethers.utils.parseEther("1.4286"),      // 70% LTV == 3.33x EE
      REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.2049"),   // 83% LTV == 5.88x EE
      REBALANCE_AL_CEILING: ethers.utils.parseEther("1.3334"), // 75% LTV == 4x EE

      MORPHO_BORROW_LEND: {
        LIQUIDATION_LTV: ethers.utils.parseEther("0.86"), // 86% LTV
        SAFE_LTV: ethers.utils.parseEther("0.835"), // 83.5% LTV
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
  },
}