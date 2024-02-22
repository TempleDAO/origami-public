export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    OVERLORD: string;
    CIRCUIT_BREAKER_PROXY: string;
    TOKEN_PRICES: string;
    SWAPPER_1INCH: string;
  },
  OV_USDC: {
    TOKENS: {
      OV_USDC_TOKEN: string;
      O_USDC_TOKEN: string;
      IUSDC_DEBT_TOKEN: string;
    },
    SUPPLY: {
      SUPPLY_MANAGER: string;
      REWARDS_MINTER: string;
      IDLE_STRATEGY_MANAGER: string;
      AAVE_V3_IDLE_STRATEGY: string;
    },
    BORROW: {
        LENDING_CLERK: string;
        CIRCUIT_BREAKER_USDC_BORROW: string;
        CIRCUIT_BREAKER_OUSDC_EXIT: string;
        GLOBAL_INTEREST_RATE_MODEL: string;
    },
  },
  LOV_DSR: {
    LOV_DSR_TOKEN: string;
    LOV_DSR_MANAGER: string;
    LOV_DSR_IR_MODEL: string;
  },
  ORACLES: {
    DAI_USD: string;
    IUSDC_USD: string;
    DAI_IUSDC: string;
  },
  EXTERNAL: {
    MAKER_DAO: {
      DAI_TOKEN: string;
      SDAI_TOKEN: string;
    },
    CIRCLE: {
      USDC_TOKEN: string;
    },
    CHAINLINK: {
      DAI_USD_ORACLE: string;
      USDC_USD_ORACLE: string;
      ETH_USD_ORACLE: string;
    },
  },
}
