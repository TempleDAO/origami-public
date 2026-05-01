type Address = `0x${string}`;

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V3: Address;
      V4: Address;
    };
  };

  VAULTS: {
    SUSDSpS: {
      OVERLORD_WALLET: Address;
      TOKEN: Address;
      MANAGER: Address;
      COW_SWAPPER: Address;
    };
    hOHM: {
      TOKEN: Address;
      MANAGER: Address;
      SWEEP_SWAPPER: Address;
      DUMMY_DEX_ROUTER: Address;
      TELEPORTER: Address;
    }
  };
    
  EXTERNAL: {
    WETH_TOKEN: Address;
    
    SKY: {
      USDS_TOKEN: Address;
      SUSDS_TOKEN: Address;
      SKY_TOKEN: Address;
      SDAO_TOKEN: Address;
      DAI_TO_USDS: Address;

      STAKING_FARMS: {
        USDS_SKY: Address;
        USDS_SDAO: Address;
      };
    };
  
    COW_SWAP: {
      VAULT_RELAYER: Address;
      SETTLEMENT: Address;
    };

    OLYMPUS: {
      OHM_TOKEN: Address;
      GOHM_TOKEN: Address;
      MONO_COOLER: Address;
    };

    LAYER_ZERO: {
      ENDPOINT: Address;
    }
  };
}
