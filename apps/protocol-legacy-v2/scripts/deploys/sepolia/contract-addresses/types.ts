interface IType {
  OVERLORD_WALLET: string;
  TOKEN: string;
  MANAGER: string;
}

export interface ContractAddresses {
  CORE: {
    MULTISIG: string;
    FEE_COLLECTOR: string;
    TOKEN_PRICES: {
      V3: string;
    };
  },

  VAULTS: {
    SUSDSpS: {
      OVERLORD_WALLET: string;
      TOKEN: string;
      MANAGER: string;
      COW_SWAPPER: string;
    },
  },
    
  EXTERNAL: {
    SKY: {
      USDS_TOKEN: string;
      SUSDS_TOKEN: string;
      SKY_TOKEN: string;
      SDAO_TOKEN: string;

      STAKING_FARMS: {
        USDS_SKY: string;
        USDS_SDAO: string;
      };
    },
  
    COW_SWAP: {
      VAULT_RELAYER: string;
      SETTLEMENT: string;
    },
  },
}
