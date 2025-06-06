import { BigNumber, ethers } from "ethers";

export const DEFAULT_SETTINGS = {
    VAULTS: {
      SUSDSpS: {
        TOKEN_SYMBOL: "sUSDS+s",
        TOKEN_NAME: "Origami sUSDS + Sky Farms",
        SWITCH_FARM_COOLDOWN_SECS: 86_400, // 1 day
        PERFORMANCE_FEE_FOR_CALLER_BPS: 100,
        PERFORMANCE_FEE_FOR_ORIGAMI_BPS: 400,

        COW_SWAPPERS: {
          // Sell exactly 10k SKY and Buy a min of 500 USDS
          EXACT_SKY_TO_USDS: {
            MAX_SELL_AMOUNT: ethers.utils.parseUnits("10000", 18), 
            MIN_BUY_AMOUNT: ethers.utils.parseUnits("500", 18),
            PARTIALLY_FILLABLE: false,
            USE_CURRENT_BALANCE_FOR_SELL_AMOUNT: false, // We want it to be exact not based off balance
            LIMIT_PRICE_PREMIUM_BPS: 0,
            VERIFY_SLIPPAGE_BPS: 0,
            ROUND_DOWN_DIVISOR: 0,
            EXPIRY_PERIOD_SECS: 60*5, // 5 minutes
            // https://api.cow.fi/mainnet/api/v1/app_data/0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf
            APP_DATA: "0x0609da86e2234e72a1e230a0591bec8a3c2e99c9f47b60e6bb41df96e9097dbf",
          }
        }
      },
      hOHM: {
        TOKEN_SYMBOL: "hOHM",
        TOKEN_NAME: "Origami hOHM",
        PERFORMANCE_FEE_BPS: 330, // 3.3%
        EXIT_FEE_BPS: 100, // 1%

        // 1 hOHM = 0.000003714158 gOHM
        SEED_GOHM_AMOUNT: ethers.utils.parseEther("10"),

        // 1 hOHM = 0.011 USDS
        SEED_USDS_AMOUNT: ethers.utils.parseEther("10") // The SEED_GOHM_AMOUNT
          .mul(ethers.utils.parseEther("2961.64")) // The origination LTV of cooler
          .div(ethers.utils.parseEther("1")),

        SEED_SHARES_AMOUNT: ethers.utils.parseEther("10") // The SEED_GOHM_AMOUNT
          .mul(ethers.utils.parseEther("269.24")) // OHM per gOHM
          .mul(1_000) // Intentionally scaling the share price by 1000
          .div(ethers.utils.parseEther("1")),

        MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256,

        SWEEP_COOLDOWN_SECS: 86400, // 1 day
        SWEEP_MAX_SELL_AMOUNT: ethers.utils.parseEther("10000"), // 10k USDS per day
      },
    },

    EXTERNAL: {
      SUSDS_INTEREST_RATE: ethers.utils.parseEther("0.05"),  // 5% APR, testnet only
    },
}