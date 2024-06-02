export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    TOKEN_PRICES: string;
  },
  ORACLES: {
    USDE_DAI: string;
    SUSDE_DAI: string;
    WEETH_WETH: string;
    EZETH_WETH: string;
    STETH_WETH: string;
    WSTETH_WETH: string;
  },
  SWAPPERS: {
    ERC4626_AND_1INCH_SWAPPER: string,
    DIRECT_1INCH_SWAPPER: string;
  },
  FLASHLOAN_PROVIDERS: {
    SPARK: string;
  },
  LOV_SUSDE_A: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_SUSDE_B: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_USDE_A: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_USDE_B: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_WEETH_A: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_EZETH_A: {
    OVERLORD_WALLET: string;
    MORPHO_BORROW_LEND: string;
    TOKEN: string;
    MANAGER: string;
  },
  LOV_WSTETH_A: {
    OVERLORD_WALLET: string;
    TOKEN: string;
    SPARK_BORROW_LEND: string;
    MANAGER: string;
  },
  EXTERNAL: {
    WETH_TOKEN: string;
    MAKER_DAO: {
      DAI_TOKEN: string;
      SDAI_TOKEN: string;
    },
    ETHENA: {
      USDE_TOKEN: string;
      SUSDE_TOKEN: string;
    },
    ETHERFI: {
      WEETH_TOKEN: string;
      LIQUIDITY_POOL: string;
    },
    LIDO: {
      STETH_TOKEN: string;
      WSTETH_TOKEN: string;
    },
    RENZO: {
      EZETH_TOKEN: string;
      RESTAKE_MANAGER: string;
    },
    REDSTONE: {
      USDE_USD_ORACLE: string;
      SUSDE_USD_ORACLE: string;
      WEETH_WETH_ORACLE: string;
      WEETH_USD_ORACLE: string;
      EZETH_WETH_ORACLE: string;
    },
    CHAINLINK: {
      ETH_USD_ORACLE: string;
      STETH_ETH_ORACLE: string;
    },
    MORPHO: {
      SINGLETON: string;
      IRM: string;
      ORACLE: {
        SUSDE_DAI: string;
        USDE_DAI: string;
        WEETH_WETH: string;
        EZETH_WETH: string;
      },
    },
    SPARK: {
      POOL_ADDRESS_PROVIDER: string;
    },
    ONE_INCH: {
      ROUTER_V6: string;
    },
  },
}
