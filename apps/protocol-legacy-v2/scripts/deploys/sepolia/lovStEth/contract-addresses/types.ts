export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    OVERLORD: string;
    TOKEN_PRICES: string;
    SWAPPER_1INCH: string;
    SPARK_FLASH_LOAN_PROVIDER: string;
  },
  ORACLES: {
    STETH_ETH: string;
    WSTETH_ETH: string;
  },
  LOV_STETH: {
    TOKEN: string;
    SPARK_BORROW_LEND: string;
    MANAGER: string;
  },
  EXTERNAL: {
    WETH_TOKEN: string;
    LIDO: {
      ST_ETH_TOKEN: string;
      WST_ETH_TOKEN: string;
    },
    CHAINLINK: {
      STETH_ETH_ORACLE: string;
      ETH_USD_ORACLE: string;
    },
  },
}
