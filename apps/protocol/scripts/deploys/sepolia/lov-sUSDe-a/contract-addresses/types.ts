export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    OVERLORD: string;
    TOKEN_PRICES: string;
    SWAPPER_1INCH: string;
  },
  ORACLES: {
    USDE_DAI: string;
    SUSDE_DAI: string;
  },
  LOV_SUSDE: {
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
      SUSDE_TOKEN: string;
    },
    REDSTONE: {
      USDE_USD_ORACLE: string;
      SUSDE_USD_ORACLE: string;
    },
    MORPHO: {
      SINGLETON: string;
      IRM: string;
      ORACLE: string;
    }
  },
}
