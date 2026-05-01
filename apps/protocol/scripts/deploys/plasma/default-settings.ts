import { ethers } from "ethers";

export const DEFAULT_SETTINGS = {
  VAULTS: {
    OPAL_PT_SUSDE_PLASMA_A: {
      TOKEN_SYMBOL: "opal-PT-sUSDe-PLASMA-a",
      TOKEN_NAME: "OPAL PT-sUSDe-PLASMA (a)",
      AUM_FEE_BPS: 50, // 0.5%
      JOIN_FEE_BPS: 0,
      EXIT_FEE_BPS: 0,

      MAX_UR_ON_JOIN: {
        "AAVE_V3.1: [sUSDe]/[USDT0]": ethers.utils.parseEther("0.9"), // 90%
        "AAVE_V3.1: [PT-sUSDE-9APR2026]/[USDT0]": ethers.utils.parseEther("0.92"), // 92%
        "AAVE_V3.1: [PT-sUSDE-18JUN2026]/[USDT0]": ethers.utils.parseEther("0.92"), // 92%
      },

      SEED_COLLATERAL_AMOUNT: ethers.utils.parseEther("82.239964377296207872"), // [sUSDe]
      TARGET_LEVERAGE: ethers.utils.parseEther("0.89"), // 89%
      MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256,
    },
    
    OPAL_SUSDE_MERKL_PLASMA_A: {
      TOKEN_SYMBOL: "opal-sUSDe-merkl-PLASMA-a",
      TOKEN_NAME: "OPAL sUSDe-merkl-PLASMA (a)",
      AUM_FEE_BPS: 50, // 0.5%
      JOIN_FEE_BPS: 0,
      EXIT_FEE_BPS: 0,

      MAX_UR_ON_JOIN: {
        "AAVE_V3.1: [sUSDe, USDe]/[USDT0]": ethers.utils.parseEther("0.9"), // 90%
      },

      SEED_COLLATERAL0_AMOUNT: ethers.utils.parseEther("174.508240040629595477"), // [sUSDe]
      TARGET_LEVERAGE: ethers.utils.parseEther("0.89"), // 89%
      MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256,
    },
  },

  ORACLES: {
    PT_SUSDE_9APR2026_USDE: {
      TWAP_DURATION_SECS: 900,
    },
    PT_SUSDE_18JUN2026_USDE: {
      TWAP_DURATION_SECS: 900,
    },
  },

  EXTERNAL: {
    CHAINLINK: {
      XPL_USD_ORACLE: {
        // https://data.chain.link/feeds/plasma/mainnet/xpl-usd
        STALENESS_THRESHOLD: 86400 + 300 // 24 hrs + 5 minutes
      },
      USDT0_USD_ORACLE: {
        // https://data.chain.link/feeds/plasma/mainnet/usdt0-usd
        STALENESS_THRESHOLD: 86400 + 300 // 24 hrs + 5 minutes
      },
      USDE_USD_ORACLE: {
        // https://data.chain.link/feeds/plasma/mainnet/usde-usd
        STALENESS_THRESHOLD: 86400 + 300 // 24 hrs + 5 minutes
      },
      SUSDE_USD_ORACLE: {
        // https://data.chain.link/feeds/plasma/mainnet/susde-usd
        STALENESS_THRESHOLD: 86400 + 300 // 24 hrs + 5 minutes
      },
    },
    AAVE: {
      PLASMA: {
        // https://plasmascan.to/address/0xdA549478Fd5C2BdB9e5eB000D0ff2554771598C7#readContract
        // getEModes(0x061D8e131F26512348ee5FA42e2DF1bA9d6505E9)
        EMODES: {
          DEFAULT: 0,
          "sUSDe Stablecoins": 2,
          "PT_sUSDe_9APR2026__Stablecoins": 15,
          "PT_sUSDE_18JUN2026__Stablecoins": 23,
        },
      }
    },
  },
};
