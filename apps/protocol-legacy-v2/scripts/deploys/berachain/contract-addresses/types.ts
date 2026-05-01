export type Address = `0x${string}`;

export interface IType {
  OVERLORD_WALLET: Address;
  TOKEN: Address;
  MANAGER: Address;
}

export interface IEulerV2Type extends IType {
  EULER_V2_BORROW_LEND: Address;
}

export interface InfraredAutoCompounderVault {
  OVERLORD_WALLET: Address;
  TOKEN: Address;
  MANAGER: Address;
  SWAPPER: Address;
};

export interface InfraredAutoStakerVault {
  VAULT: Address;

  // Auto-stakers only require a swapper (and overlord perms)
  // if the underlying reward vault has non-oriBGT rewards
  // and is in 'single reward mode'
  OVERLORD_WALLET?: Address;
  SWAPPER?: Address;
};

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V3: Address;
      V4: Address;
      V5: Address;
    },
  },
  SWAPPERS: {
    DIRECT_SWAPPER: Address,
  },
  ORACLES: {
    ORIBGT_IBGT: Address,
    ORIBGT_WBERA: Address,
    IBGT_WBERA: Address,
    IBGT_WBERA_WITH_PRICE_CHECK: Address,
  },

  LOV_ORIBGT_A: IEulerV2Type;

  VAULTS: {
    hOHM: {
      TOKEN: Address;
    };
    BOYCO_USDC_A: {
      OVERLORD_WALLET: Address;
      BEX_POOL_HELPERS: {
        HONEY_USDC: Address;
        HONEY_BYUSD: Address;
      };
      INFRARED_REWARDS_VAULT_PROXIES: {
        HONEY_USDC: Address;
        HONEY_BYUSD: Address;
      };
      BERA_BGT_PROXY: Address;
      TOKEN: Address;
      MANAGER: Address;
    };
    ORIBGT: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_IBERA_OSBGT_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A: InfraredAutoCompounderVault;
    INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A: InfraredAutoCompounderVault;

    INFRARED_AUTO_STAKING_OHM_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_BYUSD_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_RUSD_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBERA_IBERA_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBERA_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBERA_IBGT_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_IBERA_OSBGT_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_EWBERA_4_OSBGT_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_IBERA_IBGT_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_HOHM_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_SOLVBTCBNB_XSOLVBTC_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBTC_WETH_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WETH_WBERA_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBTC_HONEY_A: InfraredAutoStakerVault;
    INFRARED_AUTO_STAKING_WBTC_WBERA_A: InfraredAutoStakerVault;
  };

  FACTORIES: {
    INFRARED_AUTO_COMPOUNDER: {
      VAULT_DEPLOYER: Address;
      MANAGER_DEPLOYER: Address;
      SWAPPER_DEPLOYER: Address;
      FACTORY: Address;
    };
    INFRARED_AUTO_STAKING: {
      VAULT_DEPLOYER: Address;
      SWAPPER_DEPLOYER: Address;
      FACTORY: Address;
    };
  };

  PERIPHERY: {
    LANTERN_OFFERING: Address;
  };

  EXTERNAL: {
    CIRCLE: {
      USDC_TOKEN: Address;
    };
    PAYPAL: {
      BYUSD_TOKEN: Address;
    };
    BERACHAIN: {
      WBERA_TOKEN: Address;
      HONEY_TOKEN: Address;
      HONEY_FACTORY: Address;
      HONEY_FACTORY_READER: Address;
      BGT_TOKEN: Address;
      REWARD_VAULTS: {
        HONEY_USDC: Address;
        HONEY_BYUSD: Address;
      };
    };
    INFRARED: {
      INFRARED: Address;
      IBGT_TOKEN: Address;
      IBGT_VAULT: Address;
      IBERA_TOKEN: Address;
      REWARD_VAULTS: {
        HONEY_USDC: Address;
        HONEY_BYUSD: Address;
        OHM_HONEY: Address;
        BYUSD_HONEY: Address;
        RUSD_HONEY: Address;
        WBERA_IBERA: Address;
        WBERA_HONEY: Address;
        WBERA_IBGT: Address;
        IBERA_OSBGT: Address;
        EWBERA_4_OSBGT: Address;
        IBERA_IBGT: Address;
        HOHM_HONEY: Address;
        SOLVBTCBNB_XSOLVBTC: Address;
        WBTC_WETH: Address;
        WETH_WBERA: Address;
        WBTC_HONEY: Address;
        WBTC_WBERA: Address;
      };
    };
    BEX: {
      BALANCER_VAULT: Address;
      BALANCER_QUERIES: Address;
      LP_TOKENS: {
        HONEY_USDC: Address;
        HONEY_BYUSD: Address;
      };
    };
    KODIAK: {
      ISLAND_ROUTER: Address;
      POOLS: {
        WBERA_IBGT_V3: Address;
        OHM_HONEY_V3: Address;
        RUSD_HONEY_V3: Address;
        IBERA_WBERA_V3: Address;
        OHM_HOHM_V3: Address;
        HOHM_HONEY_V3: Address;
        WBTC_HONEY_V3: Address;
        SOLVBTCBNB_XSOLVBTC_V3: Address;
        SOLVBTC_WBTC_V3: Address;
        SOLVBTCBNB_SOLVBTC_V3: Address;
        SOLVBTC_XSOLVBTC_V3: Address;
        WBTC_WETH_V3: Address;
        WETH_WBERA_V3: Address;
        WBTC_WBERA_V3: Address;
      };
      ISLANDS: {
        OHM_HONEY_V3: Address;
        RUSD_HONEY_V3: Address;
        WBERA_IBERA_V3: Address;
        WBERA_HONEY_V3: Address;
        WBERA_IBGT_V3: Address;
        IBERA_OSBGT_V3: Address;
        EWBERA_4_OSBGT_V3: Address;
        IBERA_IBGT_V3: Address;
        OHM_HOHM_V3: Address;
        HOHM_HONEY_V3: Address;
        WBTC_HONEY_V3: Address;
        SOLVBTCBNB_XSOLVBTC_V3: Address;
        SOLVBTC_WBTC_V3: Address;
        SOLVBTCBNB_SOLVBTC_V3: Address;
        SOLVBTC_XSOLVBTC_V3: Address;
        WBTC_WETH_V3: Address;
        WETH_WBERA_V3: Address;
        WBTC_WBERA_V3: Address;
      };
    };
    REDSTONE: {
      USDC_USD_ORACLE: Address;
      HONEY_USD_ORACLE: Address;
      BERA_USD_ORACLE: Address;
      ETH_USD_ORACLE: Address;
    };
    OOGABOOGA: {
      ROUTER: Address;
    };
    OLYMPUS: {
      OHM_TOKEN: Address;
    };
    RESERVIOR: {
      RUSD_TOKEN: Address;
    };
    OPENSTATE: {
      OSBGT_TOKEN: Address;
    };
    MAGPIE: {
      ROUTER_V2: Address;
      ROUTER_V3_1: Address;
    };
    CHRONICLE: {
      IBGT_WBERA_ORACLE: Address;
    };
    KYBERSWAP: {
      ROUTER_V2: Address;
    };
    EULER_V2: {
      EVC: Address;
      MARKETS: {
        TULIPA_FOLDING_HIVE: {
          VAULTS: {
            ORIBGT: Address;
            WBERA: Address;
          };
        };
        MEV_CAPITAL_BERACHAIN_RED_CLUSTER: {
          VAULTS: {
            ORIBGT: Address;
          };
        };
      };
    };
    LAYER_ZERO: {
      ENDPOINT: Address;
    };
    SOLV: {
      XSOLVBTC_TOKEN: Address;
      SOLVBTCBNB_TOKEN: Address;
      SOLVBTC_TOKEN: Address;
    };
    BITCOIN: {
      WBTC_TOKEN: Address;
    };
    ETHEREUM: {
      WETH_TOKEN: Address;
    };
  };
};
