type Address = `0x${string}`;

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V3: Address;
    },
  },

  VAULTS: {
    BOYCO_USDC_A: {
      OVERLORD_WALLET: Address;
      BEX_POOL_HELPERS: {
        HONEY_USDC: Address;
      };
      INFRARED_REWARDS_VAULT_PROXIES: {
        HONEY_USDC: Address;
      };
      BERA_BGT_PROXY: Address;
      TOKEN: Address;
      MANAGER: Address;
    };
  };

  EXTERNAL: {
    CIRCLE: {
      USDC_TOKEN: Address;
    };
    BERACHAIN: {
      WBERA_TOKEN: Address;
      HONEY_TOKEN: Address;
      HONEY_FACTORY: Address;
      HONEY_FACTORY_READER: Address;
      BGT_TOKEN: Address;
      REWARD_VAULTS: {
        HONEY_USDC: Address;
      };
    };
    INFRARED: {
      REWARD_VAULTS: {
        HONEY_USDC: Address;
      };
    };
    BEX: {
      BALANCER_VAULT: Address;
      BALANCER_QUERIES: Address;
      LP_TOKENS: {
        HONEY_USDC: Address;
      };
    };
  };
};
