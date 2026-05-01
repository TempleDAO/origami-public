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
      }
    },

    EXTERNAL: {
      SUSDS_INTEREST_RATE: ethers.utils.parseEther("0.05"),  // 5% APR, testnet only
    },
}