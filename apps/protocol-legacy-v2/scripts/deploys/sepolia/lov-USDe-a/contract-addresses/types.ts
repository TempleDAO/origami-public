export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    OVERLORD: string;
    TOKEN_PRICES: string;
  },
  ORACLES: {
    USDE_DAI: string;
  },
  LOV_USDE: {
    SWAPPER_1INCH: string;
    TOKEN: string;
    MORPHO_BORROW_LEND: string;
    MANAGER: string;
  },
  EXTERNAL: {
    MAKER_DAO: {
      DAI_TOKEN: string;
    },
    ETHENA: {
      USDE_TOKEN: string;
    },
    REDSTONE: {
      USDE_USD_ORACLE: string;
    },
    MORPHO: {
      SINGLETON: string;
      IRM: string;
      USDE_USD_ORACLE: string;
    }
  },
}
