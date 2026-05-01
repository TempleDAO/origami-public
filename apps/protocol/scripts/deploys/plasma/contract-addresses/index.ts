import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  IPoolAddressesProvider, IPoolAddressesProvider__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  OpalAdapterFactory__factory,
  OpalAdapterFactory,
  OpalVault__factory,
  OpalManager__factory,
  OpalVault,
  OpalManager,
  OpalAdapterAaveV3,
  OpalAdapterAaveV3__factory,
  IERC4626, IERC4626__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses, IOpalVault as IOpalVaultAddr } from "./types";
import { CONTRACTS as PLASMA_CONTRACTS } from "./plasma";

const CHAIN_NAME = "plasma";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == CHAIN_NAME || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === CHAIN_NAME) {
    return PLASMA_CONTRACTS;
  } else if (network.name === 'localhost') {
    return PLASMA_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === CHAIN_NAME) {
    return PLASMA_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(PLASMA_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface IOpalVault { 
  TOKEN: OpalVault;
  MANAGER: OpalManager;
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V1: TokenPrices;
    };
  };
  
  VAULTS: {
    OPAL_PT_SUSDE_PLASMA_A: IOpalVault;
    OPAL_SUSDE_MERKL_PLASMA_A: IOpalVault;
  };

  OPAL: {
    ADAPTER_FACTORY: OpalAdapterFactory;
    ADAPTER_IMPLEMENTATIONS: {
      AAVE_V3: {
        V1: OpalAdapterAaveV3;
      };
    };
  };

  EXTERNAL: {
    WXPL_TOKEN: IERC20Metadata;
    TETHER: {
      USDT0_TOKEN: IERC20Metadata;
    };
    ETHENA: {
      USDE_TOKEN: IERC20Metadata;
      SUSDE_TOKEN: IERC4626;
    };
    AAVE: {
      V3_PLASMA_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider;
    };
    PENDLE: {
      SUSDE_9APR2026: {
        PT_TOKEN: IERC20Metadata;
      };
      SUSDE_18JUN2026: {
        PT_TOKEN: IERC20Metadata;
      };
    };
  };
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

function opalVault(
  vault: IOpalVaultAddr,
  owner: Signer
) {
  return {
    TOKEN: OpalVault__factory.connect(vault.TOKEN.address, owner),
    MANAGER: OpalManager__factory.connect(vault.MANAGER.address, owner),
  };
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    CORE: {
      TOKEN_PRICES: {
          V1: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V1, owner),
        },
    },

    VAULTS: {
      OPAL_PT_SUSDE_PLASMA_A: opalVault(ADDRS.VAULTS.OPAL_PT_SUSDE_PLASMA_A, owner),
      OPAL_SUSDE_MERKL_PLASMA_A: opalVault(ADDRS.VAULTS.OPAL_SUSDE_MERKL_PLASMA_A, owner),
    },

    OPAL: {
      ADAPTER_FACTORY: OpalAdapterFactory__factory.connect(ADDRS.OPAL.ADAPTER_FACTORY, owner),
      ADAPTER_IMPLEMENTATIONS: {
        AAVE_V3: {
          V1: OpalAdapterAaveV3__factory.connect(ADDRS.OPAL.ADAPTER_IMPLEMENTATIONS.AAVE_V3.V1, owner),
        },
      },
    },
    
    EXTERNAL: {
      WXPL_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.WXPL_TOKEN, owner),
      TETHER: {
        USDT0_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.TETHER.USDT0_TOKEN, owner),
      },
      ETHENA: {
        USDE_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, owner),
        SUSDE_TOKEN: IERC4626__factory.connect(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, owner),
      },
      AAVE: {
        V3_PLASMA_POOL_ADDRESS_PROVIDER: IPoolAddressesProvider__factory.connect(ADDRS.EXTERNAL.AAVE.V3_PLASMA_POOL_ADDRESS_PROVIDER, owner),
      },
      PENDLE: {
        SUSDE_9APR2026: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.SUSDE_9APR2026.PT_TOKEN, owner),
        },
        SUSDE_18JUN2026: {
          PT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.PENDLE.SUSDE_18JUN2026.PT_TOKEN, owner),
        },
      },
    },
  };
}
