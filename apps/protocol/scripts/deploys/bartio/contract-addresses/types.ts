type Address = `0x${string}`;

interface IType {
  OVERLORD_WALLET: Address;
  TOKEN: Address;
  MANAGER: Address;
}

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V3: Address;
    },
  },
  
  LOV_HONEY_A: IType;
  LOV_WBERA_LONG_A: IType;
  LOV_YEET_A: IType;
  LOV_WBTC_LONG_A: IType;
  LOV_WETH_LONG_A: IType;
  LOV_LOCKS_A: IType;

  VAULTS: {
    BOYCO_HONEY_A: {
      OVERLORD_WALLET: Address;
      BEX_POOL_HELPER: Address;
      BERA_REWARDS_STAKER: Address;
      TOKEN: Address;
      MANAGER: Address;
    };
  };

  EXTERNAL: {
    BERACHAIN: {
      WBERA_TOKEN: Address;
      HONEY_TOKEN: Address;
      BGT_TOKEN: Address;
      HONEY_MINTER: Address;
      BEX: {
        VAULT: Address;
        QUERY_HELPER: Address;
        HONEY_USDC_LP_TOKEN: Address;
        HONEY_USDC_REWARDS_VAULT: Address;
      };
    },
    CIRCLE: {
      USDC_TOKEN: Address;
    },
    GOLDILOCKS: {
      LOCKS_TOKEN: Address;
    },
    YEET: {
      YEET_TOKEN: Address;
    },
    WETH_TOKEN: Address;
    WBTC_TOKEN: Address;
  },
}
