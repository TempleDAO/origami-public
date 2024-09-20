interface IType {
  OVERLORD_WALLET: string;
  TOKEN: string;
  MANAGER: string;
}

interface IMorphoType extends IType {
  MORPHO_BORROW_LEND: string;
};

interface ISparkType extends IType {
  SPARK_BORROW_LEND: string;
};

export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    TOKEN_PRICES: {
      V1: string;
      V2: string;
      V3: string;
    };
  },
  ORACLES: {
    USDE_DAI: string;
    SUSDE_DAI: string;
    WEETH_WETH: string;
    EZETH_WETH: string;
    STETH_WETH: string;
    WSTETH_WETH: string;
    WOETH_WETH: string;
    DAI_USD: string;
    WETH_DAI: string;
    WBTC_DAI: string;
    WETH_WBTC: string;
    SDAI_DAI: string;
    WETH_SDAI: string;
    WBTC_SDAI: string;
    PT_SUSDE_OCT24_USDE: string;
    PT_SUSDE_OCT24_DAI: string;
    MKR_DAI: string;
    AAVE_USDC: string;
    SDAI_USDC: string;
    USD0pp_USD0: string;
    USD0pp_USDC: string;
    USD0_USDC: string;
    RSWETH_WETH: string;
    SUSDE_USD_INTERNAL: string;
    SDAI_USD_INTERNAL: string;
    SDAI_SUSDE: string;
  },
  SWAPPERS: {
    DIRECT_SWAPPER: string;
    SUSDE_SWAPPER: string;
  },
  FLASHLOAN_PROVIDERS: {
    SPARK: string;

    // Aave charge a 5bps fee on this - so prefer not to use it.
    AAVE_V3_MAINNET_HAS_FEE: string;
    MORPHO: string;
  },
  LOV_SUSDE_A: IMorphoType;
  LOV_SUSDE_B: IMorphoType;
  LOV_USDE_A: IMorphoType;
  LOV_USDE_B: IMorphoType;
  LOV_WEETH_A: IMorphoType;
  LOV_EZETH_A: IMorphoType;
  LOV_WSTETH_A: ISparkType;
  LOV_WSTETH_B: ISparkType;
  LOV_WOETH_A: IMorphoType;
  LOV_WETH_DAI_LONG_A: ISparkType;
  LOV_WETH_SDAI_SHORT_A: ISparkType;
  LOV_WBTC_DAI_LONG_A: ISparkType;
  LOV_WBTC_SDAI_SHORT_A: ISparkType;
  LOV_WETH_WBTC_LONG_A: ISparkType;
  LOV_WETH_WBTC_SHORT_A: ISparkType;
  LOV_PT_SUSDE_OCT24_A: IMorphoType;
  LOV_MKR_DAI_LONG_A: ISparkType;
  LOV_AAVE_USDC_LONG_A: ISparkType;
  LOV_SDAI_A: IMorphoType;
  LOV_USD0pp_A: IMorphoType;
  LOV_RSWETH_A: IMorphoType;

  EXTERNAL: {
    WETH_TOKEN: string;
    WBTC_TOKEN: string;
    INTERNAL_USD: string;
    MAKER_DAO: {
      DAI_TOKEN: string;
      SDAI_TOKEN: string;
      MKR_TOKEN: string;
    },
    CIRCLE: {
      USDC_TOKEN: string;
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
    ORIGIN: {
      OETH_TOKEN: string;
      WOETH_TOKEN: string;
    },
    USUAL: {
      USD0pp_TOKEN: string;
      USD0_TOKEN: string;
    },
    CURVE: {
      USD0pp_USD0_STABLESWAP_NG: string;
      USD0_USDC_STABLESWAP_NG: string;
    },
    SWELL: {
      RSWETH_TOKEN: string;
    }
    REDSTONE: {
      USDE_USD_ORACLE: string;
      SUSDE_USD_ORACLE: string;
      WEETH_WETH_ORACLE: string;
      WEETH_USD_ORACLE: string;
      EZETH_WETH_ORACLE: string;
    },
    CHAINLINK: {
      DAI_USD_ORACLE: string;
      ETH_USD_ORACLE: string;
      BTC_USD_ORACLE: string;
      ETH_BTC_ORACLE: string;
      STETH_ETH_ORACLE: string;
      MKR_USD_ORACLE: string;
      AAVE_USD_ORACLE: string;
      USDC_USD_ORACLE: string;
    },
    ORIGAMI_ORACLE_ADAPTERS: {
      RSWETH_ETH_EXCHANGE_RATE: string;
    },
    MORPHO: {
      SINGLETON: string;
      IRM: string;
      ORACLE: {
        SUSDE_DAI: string;
        USDE_DAI: string;
        WEETH_WETH: string;
        EZETH_WETH: string;
        WOETH_WETH: string;
        PT_SUSDE_OCT24_DAI: string;
        SDAI_USDC: string;
        USD0pp_USDC: string;
        RSWETH_WETH: string;
      },
    },
    PENDLE: {
      ORACLE: string;
      ROUTER: string;
      SUSDE_OCT24: {
        MARKET: string;
        PT_TOKEN: string;
      },
    },
    SPARK: {
      POOL_ADDRESS_PROVIDER: string;
    },
    AAVE: {
      AAVE_TOKEN: string;
      V3_MAINNET_POOL_ADDRESS_PROVIDER: string;
      V3_LIDO_POOL_ADDRESS_PROVIDER: string;
    },
    ONE_INCH: {
      ROUTER_V6: string;
    },
    KYBERSWAP: {
      ROUTER_V2: string;
    },
    COW_SWAP: {
      VAULT_RELAYER: string;
      SETTLEMENT: string;
    },
  },

  MAINNET_TEST: {
    SWAPPERS: {
      COW_SWAPPER_1: string;
      COW_SWAPPER_2: string;
    };
  };
}
