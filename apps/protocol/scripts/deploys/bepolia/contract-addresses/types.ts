type Address = `0x${string}`;

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
  };

  VAULTS: {
    hOHM: {
      TOKEN: Address;
    }
  }

  EXTERNAL: {
    LAYER_ZERO: {
      ENDPOINT: Address;
    }
  };
}
