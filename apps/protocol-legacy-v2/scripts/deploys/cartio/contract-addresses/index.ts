import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  OrigamiBoycoUsdcManager,
  OrigamiBoycoUsdcManager__factory,
  OrigamiBalancerComposableStablePoolHelper,
  OrigamiBeraBgtProxy,
  IBalancerVault,
  IBalancerQueries,
  IBalancerBptToken,
  IBeraRewardsVault,
  OrigamiBalancerComposableStablePoolHelper__factory,
  OrigamiBeraBgtProxy__factory,
  IBalancerVault__factory,
  IBalancerQueries__factory,
  IBalancerBptToken__factory,
  IBeraRewardsVault__factory,
  IWrappedToken,
  IWrappedToken__factory,
  IBeraHoneyFactory,
  IBeraHoneyFactory__factory,
  IBeraHoneyFactoryReader,
  IBeraHoneyFactoryReader__factory,
  OrigamiInfraredVaultProxy,
  OrigamiInfraredVaultProxy__factory,
  OrigamiDelegated4626Vault,
  OrigamiDelegated4626Vault__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as CARTIO_CONTRACTS } from "./cartio"; 

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "cartio" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'cartio') {
    return CARTIO_CONTRACTS;
  } else if (network.name === 'localhost') {
    return CARTIO_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'cartio') {
    return CARTIO_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(CARTIO_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V3: TokenPrices;
    };
  };

  VAULTS: {
    BOYCO_USDC_A: {
      BEX_POOL_HELPERS: {
        HONEY_USDC: OrigamiBalancerComposableStablePoolHelper;
      };
      INFRARED_REWARDS_VAULT_PROXIES: {
        HONEY_USDC: OrigamiInfraredVaultProxy;
      };
      BERA_BGT_PROXY: OrigamiBeraBgtProxy;
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiBoycoUsdcManager;
    };
  };

  EXTERNAL: {
    CIRCLE: {
      USDC_TOKEN: IERC20Metadata;
    },
    BERACHAIN: {
      WBERA_TOKEN: IWrappedToken;
      HONEY_TOKEN: IERC20Metadata;
      HONEY_FACTORY: IBeraHoneyFactory;
      HONEY_FACTORY_READER: IBeraHoneyFactoryReader;
      BGT_TOKEN: IERC20Metadata;
      REWARD_VAULTS: {
        HONEY_USDC: IBeraRewardsVault;
      };
    },
    BEX: {
      BALANCER_VAULT: IBalancerVault;
      BALANCER_QUERIES: IBalancerQueries;
      LP_TOKENS: {
        HONEY_USDC: IBalancerBptToken;
      };
    },
  },
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    CORE: {
      TOKEN_PRICES: {
          V3: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V3, owner),
        },
    },
    VAULTS: {
      BOYCO_USDC_A: {
        BEX_POOL_HELPERS: {
          HONEY_USDC: OrigamiBalancerComposableStablePoolHelper__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.BEX_POOL_HELPERS.HONEY_USDC, owner),
        },
        INFRARED_REWARDS_VAULT_PROXIES: {
          HONEY_USDC: OrigamiInfraredVaultProxy__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC, owner),
        },
        BERA_BGT_PROXY: OrigamiBeraBgtProxy__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY, owner),
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.TOKEN, owner),
        MANAGER: OrigamiBoycoUsdcManager__factory.connect(ADDRS.VAULTS.BOYCO_USDC_A.MANAGER, owner),
      },
    },
    EXTERNAL: {
      CIRCLE: {
        USDC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, owner),
      },
      BERACHAIN: {
        WBERA_TOKEN: IWrappedToken__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner),
        HONEY_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, owner),
        HONEY_FACTORY: IBeraHoneyFactory__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY, owner),
        HONEY_FACTORY_READER: IBeraHoneyFactoryReader__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_FACTORY_READER, owner),
        BGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.BGT_TOKEN, owner),
        REWARD_VAULTS: {
          HONEY_USDC: IBeraRewardsVault__factory.connect(ADDRS.EXTERNAL.BERACHAIN.REWARD_VAULTS.HONEY_USDC, owner),
        },
      },
      BEX: {
        BALANCER_VAULT: IBalancerVault__factory.connect(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, owner),
        BALANCER_QUERIES: IBalancerQueries__factory.connect(ADDRS.EXTERNAL.BEX.BALANCER_QUERIES, owner),
        LP_TOKENS: {
          HONEY_USDC: IBalancerBptToken__factory.connect(ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC, owner),
        },
      },
    },
  }
}
