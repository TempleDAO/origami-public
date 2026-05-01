import { ethers } from "ethers";

const SEED_DEPOSIT_SIZE = ethers.utils.parseUnits("10", 6); // USDC

export const DEFAULT_SETTINGS = {
  VAULTS: {
    BOYCO_USDC_A: {
      TOKEN_SYMBOL: "oboy-USDC-a",
      TOKEN_NAME: "Origami Boyco USDC",
      SEED_DEPOSIT_SIZE: SEED_DEPOSIT_SIZE,
      MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256, // Left unconstrained on bera
    },
    ORIBGT: {
      TOKEN_SYMBOL: "oriBGT",
      TOKEN_NAME: "Origami iBGT Auto-Compounder",
      PERFORMANCE_FEE: 100, // 1%
      EXIT_FEE_BPS: 0,

      SEED_DEPOSIT_SIZE: ethers.utils.parseEther("36.031043119337088645"),
      MAX_TOTAL_SUPPLY: ethers.constants.MaxUint256,
    },
    INFRARED_AUTO_COMPOUNDERS: {
      OHM_HONEY: {
        TOKEN_SYMBOL: "oAC-OHM-HONEY-a",
        TOKEN_NAME: "Origami OHM-HONEY LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.001214019317498205"),
      },
      BYUSD_HONEY: {
        TOKEN_SYMBOL: "oAC-BYUSD-HONEY-a",
        TOKEN_NAME: "Origami BYUSD-HONEY LP Auto-Compounder (BEX)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("232.565709656086033852"),
      },
      RUSD_HONEY: {
        TOKEN_SYMBOL: "oAC-rUSD-HONEY-a",
        TOKEN_NAME: "Origami rUSD-HONEY LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1788.290808655584798619"),
      },
      WBERA_IBERA: {
        TOKEN_SYMBOL: "oAC-WBERA-iBERA-a",
        TOKEN_NAME: "Origami WBERA-iBERA LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("404.427181567899688427"),
      },
      WBERA_HONEY: {
        TOKEN_SYMBOL: "oAC-WBERA-HONEY-a",
        TOKEN_NAME: "Origami WBERA-HONEY LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("54.486237361324176912"),
      },
      WBERA_IBGT: {
        TOKEN_SYMBOL: "oAC-WBERA-iBGT-a",
        TOKEN_NAME: "Origami WBERA-iBGT LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("57.243691206752966089"),
      },
      IBERA_OSBGT: {
        TOKEN_SYMBOL: "oAC-iBERA-osBGT-a",
        TOKEN_NAME: "Origami iBERA-osBGT LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1"),
      },
      EWBERA_4_OSBGT: {
        TOKEN_SYMBOL: "oAC-eWBERA-4-osBGT-a",
        TOKEN_NAME: "Origami eWBERA-4-osBGT LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("512"),
      },
      IBERA_IBGT: {
        TOKEN_SYMBOL: "oAC-iBERA-iBGT-a",
        TOKEN_NAME: "Origami iBERA-iBGT LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("70"),
      },
      HOHM_HONEY: {
        TOKEN_SYMBOL: "oAC-hOHM-HONEY-a",
        TOKEN_NAME: "Origami hOHM-HONEY LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1804"),
      },
      SOLVBTCBNB_XSOLVBTC: {
        TOKEN_SYMBOL: "oAC-SolvBTC.BNB-xSolvBTC-a",
        TOKEN_NAME: "Origami SolvBTC.BNB-xSolvBTC LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1804"),
      },
      WBTC_WETH: {
        TOKEN_SYMBOL: "oAC-WBTC-WETH-a",
        TOKEN_NAME: "Origami WBTC-WETH LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.000000030000000000"),
      },
      WETH_WBERA: {
        TOKEN_SYMBOL: "oAC-WETH-WBERA-a",
        TOKEN_NAME: "Origami WETH-WBERA LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1.5"),
      },
      WBTC_HONEY: {
        TOKEN_SYMBOL: "oAC-WBTC-HONEY-a",
        TOKEN_NAME: "Origami WBTC-HONEY LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.0000034"),
      },
      WBTC_WBERA: {
        TOKEN_SYMBOL: "oAC-WBTC-WBERA-a",
        TOKEN_NAME: "Origami WBTC-WBERA LP Auto-Compounder (Kodiak)",
        PERFORMANCE_FEE: 100, // 1%
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.0000025"),
      },
    },
    INFRARED_AUTO_STAKING: {
      PERFORMANCE_FEE: 100, // 1%
      EWBERA_4_OSBGT: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("512"),
      },
      IBERA_IBGT: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("71.153959063799677352"),
      },
      HOHM_HONEY: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1804.962483568396967923"),
      },
      SOLVBTCBNB_XSOLVBTC: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1804.962483568396967923"),
      },
      WBTC_WETH: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.000000031480752524"),
      },
      WETH_WBERA: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("1.650460155115071515"),
      },
      WBTC_HONEY: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.000003511305911391"),
      },
      WBTC_WBERA: {
        SEED_DEPOSIT_SIZE: ethers.utils.parseEther("0.000002862504909527"),
      },
    },
    hOHM: {
      TOKEN_SYMBOL: "hOHM",
      TOKEN_NAME: "Origami hOHM",
    },
  },

  LOV_ORIBGT_A: {
    TOKEN_SYMBOL: "lov-oriBGT-a",
    TOKEN_NAME: "Origami lov-oriBGT-a",

    MIN_DEPOSIT_FEE_BPS: 0, // 0%
    MIN_EXIT_FEE_BPS: 200, // 2%
    FEE_LEVERAGE_FACTOR: 0, // N/A
    PERFORMANCE_FEE_BPS: 200, // 2%

    USER_AL_FLOOR: ethers.utils.parseEther("1.3352"),         // 74.9% Market LTV == 3.98x EE
    USER_AL_CEILING: ethers.utils.parseEther("1.5385"),       // 65% Market LTV == 2.86x EE
    REBALANCE_AL_FLOOR: ethers.utils.parseEther("1.3514"),    // 74% Market LTV == 3.85x EE
    REBALANCE_AL_CEILING: ethers.utils.parseEther("1.4286"),  // 70% Market LTV == 3.33x EE

    INITIAL_MAX_TOTAL_SUPPLY: ethers.utils.parseEther("0"),        // No initial supply
    SEED_DEPOSIT_SIZE: ethers.utils.parseUnits("1000", 18),        // oriBGT (8dp)
    MAX_TOTAL_SUPPLY: ethers.utils.parseUnits("100000", 18),       // Vault is always 18dp
  },

  EXTERNAL: {
    REDSTONE: {
      USDC_USD_ORACLE: {
        STALENESS_THRESHOLD: 86400 + 300 // 24 hours + 5 minutes
      },
      HONEY_USD_ORACLE: {
        STALENESS_THRESHOLD: 86400 + 300 // 24 hours + 5 minutes
      },
      WBERA_USD_ORACLE: {
        STALENESS_THRESHOLD: 21600 + 300 // 6 hours + 5 minutes
      },
      WETH_USD_ORACLE: {
        STALENESS_THRESHOLD: 86400 + 300 // 24 hours + 5 minutes
      }
    },
    CHRONICLE: {
      IBGT_WBERA_ORACLE: {
        STALENESS_THRESHOLD: 1800 + 300 // 30 minutes + 5 minutes
      }
    },
    LAYER_ZERO: {
      ENDPOINT_ID: 30362,
    }
  },
};
