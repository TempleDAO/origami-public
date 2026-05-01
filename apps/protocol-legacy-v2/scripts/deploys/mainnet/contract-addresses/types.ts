type Address = `0x${string}`;

export interface IType {
  OVERLORD_WALLET: Address;
  TOKEN: Address;
  MANAGER: Address;
}

export interface IMorphoType extends IType {
  MORPHO_BORROW_LEND: Address;
}

export interface ISparkType extends IType {
  SPARK_BORROW_LEND: Address;
}

export interface IZeroLendType extends IType {
  ZEROLEND_BORROW_LEND: Address;
}

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V1: Address;
      V2: Address;
      V3: Address;
      V4: Address;
    };
  };
  ORACLES: {
    USDE_DAI: Address;
    SUSDE_DAI: Address;
    WEETH_WETH: Address;
    EZETH_WETH: Address;
    STETH_WETH: Address;
    WSTETH_WETH: Address;
    WOETH_WETH: Address;
    DAI_USD: Address;
    WETH_DAI: Address;
    WBTC_DAI: Address;
    WETH_WBTC: Address;
    SDAI_DAI: Address;
    WETH_SDAI: Address;
    WBTC_SDAI: Address;
    PT_SUSDE_OCT24_USDE: Address;
    PT_SUSDE_OCT24_DAI: Address;
    PT_SUSDE_MAR_2025_USDE: Address; // PT->USDe [pendle]
    PT_SUSDE_MAR_2025_DAI: Address; // PT->DAI = PT->USDe [pendle] * USDE/DAI [Restone]
    PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY: Address; // PT DiscountToMaturity [Maker]
    PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY: Address; // PT/USDe [pendle] * USDE/DAI [Restone] / DiscountToMaturity [maker]
    PT_SUSDE_MAY_2025_USDE: Address; // PT->USDe [pendle]
    PT_SUSDE_MAY_2025_DAI: Address; // PT->DAI = PT->USDe [pendle] * USDE/DAI [Restone]
    PT_SUSDE_MAY_2025_DISCOUNT_TO_MATURITY: Address; // PT DiscountToMaturity [Maker]
    PT_SUSDE_MAY_2025_DAI_WITH_DISCOUNT_TO_MATURITY: Address; // PT/USDe [pendle] * USDE/DAI [Restone] / DiscountToMaturity [maker]
    MKR_DAI: Address;
    AAVE_USDC: Address;
    SDAI_USDC: Address;
    USD0pp_USD0: Address;
    USD0pp_USDC_PEGGED: Address;
    USD0pp_USDC_FLOOR_PRICE: Address;
    USD0pp_USDC_MARKET_PRICE: Address;
    USD0pp_MORPHO_TO_MARKET_CONVERSION: Address;
    USD0_USDC: Address;
    RSWETH_WETH: Address;
    SUSDE_USD_INTERNAL: Address;
    SDAI_USD_INTERNAL: Address;
    SDAI_SUSDE: Address;
    PT_EBTC_DEC24_EBTC: Address;
    PT_CORN_LBTC_DEC24_LBTC: Address;
    WETH_CBBTC: Address;
    PT_USD0pp_MAR_2025_USD0pp: Address;
    PT_USD0pp_MAR_2025_USDC_PEGGED: Address;
    SKY_MKR: Address;
    MKR_USDS: Address;
    SKY_USDS: Address;
    PT_LBTC_MAR_2025_LBTC: Address;
  };
  SWAPPERS: {
    DIRECT_SWAPPER: Address;
    SUSDE_SWAPPER: Address;
  };
  FLASHLOAN_PROVIDERS: {
    SPARK: Address;

    // Aave charge a 5bps fee on this - so prefer not to use it.
    AAVE_V3_MAINNET_HAS_FEE: Address;
    MORPHO: Address;

    ZEROLEND_MAINNET_BTC: Address;
  };
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
  LOV_PT_SUSDE_MAR_2025_A: IMorphoType;
  LOV_PT_SUSDE_MAY_2025_A: IMorphoType;
  LOV_MKR_DAI_LONG_A: ISparkType;
  LOV_AAVE_USDC_LONG_A: ISparkType;
  LOV_SDAI_A: IMorphoType;
  LOV_USD0pp_A: IMorphoType;
  LOV_RSWETH_A: IMorphoType;
  LOV_PT_EBTC_DEC24_A: IZeroLendType;
  LOV_PT_CORN_LBTC_DEC24_A: IZeroLendType;
  LOV_WETH_CBBTC_LONG_A: ISparkType;
  LOV_PT_USD0pp_MAR_2025_A: IMorphoType;
  LOV_PT_LBTC_MAR_2025_A: IMorphoType;

  VAULTS: {
    SUSDSpS: {
      OVERLORD_WALLET: Address;
      TOKEN: Address;
      MANAGER: Address;
      COW_SWAPPER: Address;
      COW_SWAPPER_2: Address;
      COW_SWAPPER_3: Address;
      COW_SWAPPER_4: Address;
    };
    SKYp: {
      OVERLORD_WALLET: Address;
      TOKEN: Address;
      MANAGER: Address;
      COW_SWAPPER: Address;
      COW_SWAPPER_2: Address;
      COW_SWAPPER_3: Address;
    };
    hOHM: {
      OVERLORD_WALLET: Address;
      TOKEN: Address;
      MANAGER: Address;
      SWEEP_SWAPPER: Address;
      TELEPORTER: Address;
      MIGRATOR: Address;
      ARB_BOT_OVERLORD_WALLET: Address;
      ARB_BOT: Address;
    };
    OAC_USDS_IMF_MOR: {
      OVERLORD_WALLET: Address;
      TOKEN: Address;
      MANAGER: Address;
      COW_SWAPPER: Address;
    };
  };

  PERIPHERY: {
    TOKEN_RECOVERY: Address;
  };

  EXTERNAL: {
    WETH_TOKEN: Address;
    WBTC_TOKEN: Address;
    INTERNAL_USD: Address;
    MAKER_DAO: {
      DAI_TOKEN: Address;
      SDAI_TOKEN: Address;
      MKR_TOKEN: Address;
      DAI_USDS_CONVERTER: Address;
      DAI_FLASHLOAN_LENDER: Address;
    };
    SKY: {
      USDS_TOKEN: Address;
      SUSDS_TOKEN: Address;
      SKY_TOKEN: Address;

      STAKING_FARMS: {
        STAKE_USDS_EARN_SKY: Address;
        STAKE_SKY_EARN_USDS: Address;
      };

      LOCKSTAKE_ENGINE: Address;
    };
    CIRCLE: {
      USDC_TOKEN: Address;
    };
    ETHENA: {
      USDE_TOKEN: Address;
      SUSDE_TOKEN: Address;
    };
    ETHERFI: {
      WEETH_TOKEN: Address;
      LIQUIDITY_POOL: Address;
      EBTC_TOKEN: Address;
    };
    LIDO: {
      STETH_TOKEN: Address;
      WSTETH_TOKEN: Address;
    };
    RENZO: {
      EZETH_TOKEN: Address;
      RESTAKE_MANAGER: Address;
    };
    ORIGIN: {
      OETH_TOKEN: Address;
      WOETH_TOKEN: Address;
    };
    USUAL: {
      USD0pp_TOKEN: Address;
      USD0_TOKEN: Address;
    };
    CURVE: {
      USD0pp_USD0_STABLESWAP_NG: Address;
      USD0_USDC_STABLESWAP_NG: Address;
    };
    SWELL: {
      RSWETH_TOKEN: Address;
    };
    LOMBARD: {
      LBTC_TOKEN: Address;
    };
    COINBASE: {
      CBBTC_TOKEN: Address;
    };
    REDSTONE: {
      USDE_USD_ORACLE: Address;
      SUSDE_USD_ORACLE: Address;
      WEETH_WETH_ORACLE: Address;
      WEETH_USD_ORACLE: Address;
      EZETH_WETH_ORACLE: Address;
      SPK_USD_ORACLE: Address;
    };
    CHAINLINK: {
      DAI_USD_ORACLE: Address;
      ETH_USD_ORACLE: Address;
      BTC_USD_ORACLE: Address;
      ETH_BTC_ORACLE: Address;
      STETH_ETH_ORACLE: Address;
      MKR_USD_ORACLE: Address;
      AAVE_USD_ORACLE: Address;
      USDC_USD_ORACLE: Address;
      USD0pp_USD_ORACLE: Address;
    };
    ORIGAMI_ORACLE_ADAPTERS: {
      RSWETH_ETH_EXCHANGE_RATE: Address;
    };
    MORPHO: {
      SINGLETON: Address;
      IRM: Address;
      ORACLE: {
        SUSDE_DAI: Address;
        USDE_DAI: Address;
        WEETH_WETH: Address;
        EZETH_WETH: Address;
        WOETH_WETH: Address;
        PT_SUSDE_OCT24_DAI: Address;
        SDAI_USDC: Address;
        USD0pp_USDC_PEGGED: Address;
        USD0pp_USDC_FLOOR_PRICE: Address;
        USD0pp_FLOOR_PRICE_ADAPTER: Address;
        RSWETH_WETH: Address;
        PT_SUSDE_MAR_2025_DAI: Address;
        PT_SUSDE_MAY_2025_DAI: Address;
        PT_USD0pp_MAR_2025_USDC_PEGGED: Address;
        PT_LBTC_MAR_2025_LBTC: Address;
      };
      MORPHO_TOKEN: Address;
      MORPHO_LEGACY_TOKEN: Address;
      MORPHO_LEGACY_WRAPPER: Address;
      EARN_VAULTS: {
        IMF_USDS: Address;
      };
      REWARDS_DISTRIBUTOR: Address;
    };
    PENDLE: {
      ORACLE: Address;
      ROUTER: Address;
      SUSDE_OCT24: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
      SUSDE_MAR_2025: {
        MARKET: Address;
        PT_TOKEN: Address;
        DISCOUNT_TO_MATURITY_ORACLE: Address;
      };
      SUSDE_MAY_2025: {
        MARKET: Address;
        PT_TOKEN: Address;
        DISCOUNT_TO_MATURITY_ORACLE: Address;
      };
      EBTC_DEC24: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
      CORN_LBTC_DEC24: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
      USD0pp_MAR_2025: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
      LBTC_MAR_2025: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
    };
    SPARK: {
      SPK_TOKEN: Address;
      POOL_ADDRESS_PROVIDER: Address;
    };
    AAVE: {
      AAVE_TOKEN: Address;
      V3_MAINNET_POOL_ADDRESS_PROVIDER: Address;
      V3_LIDO_POOL_ADDRESS_PROVIDER: Address;
    };
    ZEROLEND: {
      MAINNET_BTC_POOL_ADDRESS_PROVIDER: Address;
    };
    ONE_INCH: {
      ROUTER_V6: Address;
    };
    KYBERSWAP: {
      ROUTER_V2: Address;
    };
    COW_SWAP: {
      VAULT_RELAYER: Address;
      SETTLEMENT: Address;
    };
    MAGPIE: {
      ROUTER_V2: Address;
      ROUTER_V3_1: Address;
    };
    OLYMPUS: {
      OHM_TOKEN: Address;
      GOHM_TOKEN: Address;
      MONO_COOLER: Address;
      COOLER_V1: {
        CLEARINGHOUSE_V1_1: Address;
        CLEARINGHOUSE_V1_2: Address;
        CLEARINGHOUSE_V1_3: Address;
      };
      GOHM_STAKING: Address;
    };
    LAYER_ZERO: {
      ENDPOINT: Address;
    };
    UNISWAP: {
      POOLS: {
        OHM_WETH_V3: Address;
        IMF_WETH_V3: Address;
      };
      ROUTER_V3: Address;
      QUOTER_V3: Address;
    };
    IMF: {
      IMF_TOKEN: Address;
    };
    MERKL: {
      REWARDS_DISTRIBUTOR: Address;
    };
  };

  MAINNET_TEST: {
    SWAPPERS: {
      COW_SWAPPER_1: Address;
      COW_SWAPPER_2: Address;
    };
  };
}
