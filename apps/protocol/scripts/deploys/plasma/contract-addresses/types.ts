export type Address = `0x${string}`;

export interface DeployedContract {
  address: Address;
  creationBlock: number;
}

export interface BundlerContracts {
  BUNDLER: Address;
  PLUGINS: {
    FLASHLOAN: {
      AAVE_V3_PLASMA: Address;
      EULER: Address;
    };
    TBS: {
      V2: Address;
    };
    SWAP: {
      KYBER: Address;
      PENDLE: Address;
    };
    ENTRY_POINT: Address;
  };
}

export interface IOpalVault {
  OVERLORD_WALLET: Address;
  TOKEN: DeployedContract;
  MANAGER: DeployedContract;
}

export interface ContractAddresses {
  CORE: {
    MULTISIG: Address;
    FEE_COLLECTOR: Address;
    TOKEN_PRICES: {
      V1: Address;
    };
    HYPERNATIVE: {
      SYSTEM_WALLET: Address;
    };
  };

  ORACLES: {
    PT_SUSDE_9APR2026_USDE: Address;
    PT_SUSDE_18JUN2026_USDE: Address;
  };

  VAULTS: {
    OPAL_PT_SUSDE_PLASMA_A: IOpalVault & {
      ADAPTER_INSTANCES: {
        "AAVE_V3.1: [sUSDe]/[USDT0]": Address;
        "AAVE_V3.1: [PT-sUSDE-9APR2026]/[USDT0]": Address;
        "AAVE_V3.1: [PT-sUSDE-18JUN2026]/[USDT0]": Address;
      };
    };
    OPAL_SUSDE_MERKL_PLASMA_A: IOpalVault & {
      ADAPTER_INSTANCES: {
        "AAVE_V3.1: [sUSDe, USDe]/[USDT0]": Address;
      };
    };
  };

  BUNDLER: BundlerContracts;

  OPAL: {
    ADAPTER_FACTORY: Address;
    ADAPTER_IMPLEMENTATIONS: {
      AAVE_V3: {
        V1: Address;
      };
      SPOT_ASSETS: {
        V1: Address;
      };
    };
  };

  EXTERNAL: {
    WXPL_TOKEN: Address;
    PERMIT2: Address;
    TETHER: {
      USDT0_TOKEN: Address;
    };
    ETHENA: {
      USDE_TOKEN: Address;
      SUSDE_TOKEN: Address;
    };
    PENDLE: {
      ORACLE: Address;
      ROUTER: Address;
      SUSDE_9APR2026: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
      SUSDE_18JUN2026: {
        MARKET: Address;
        PT_TOKEN: Address;
      };
    };
    AAVE: {
      V3_PLASMA_POOL_ADDRESS_PROVIDER: Address;
    };
    KYBERSWAP: {
      ROUTER_V2: Address;
      SCALING_HELPER: Address;
    };
    MERKL: {
      REWARDS_DISTRIBUTOR: Address;
    };
    CHAINLINK: {
      XPL_USD_ORACLE: Address;
      USDT0_USD_ORACLE: Address;
      USDE_USD_ORACLE: Address;
      SUSDE_USD_ORACLE: Address;
    };
  };
}
