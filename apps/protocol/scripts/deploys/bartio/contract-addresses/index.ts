import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  OrigamiLovToken, OrigamiLovToken__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  OrigamiTestnetLovTokenManager,
  OrigamiTestnetLovTokenManager__factory,
  OrigamiBoycoUsdcManager,
  OrigamiBoycoUsdcManager__factory,
  OrigamiDelegated4626Vault,
  OrigamiDelegated4626Vault__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as BARTIO_CONTRACTS } from "./bartio";
import { CONTRACTS as LOCALHOST_CONTRACTS } from "./localhost";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "bartio" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'bartio') {
    return BARTIO_CONTRACTS;
  } else if (network.name === 'localhost') {
    return LOCALHOST_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'bartio') {
    return BARTIO_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(BARTIO_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

interface ITestnetType {
  TOKEN: OrigamiLovToken;
  MANAGER: OrigamiTestnetLovTokenManager;
};

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V3: TokenPrices;
    },
  },
  LOV_HONEY_A: ITestnetType,
  LOV_WBERA_LONG_A: ITestnetType,
  LOV_YEET_A: ITestnetType,
  LOV_WBTC_LONG_A: ITestnetType,
  LOV_WETH_LONG_A: ITestnetType,
  LOV_LOCKS_A: ITestnetType,

  VAULTS: {
    BOYCO_HONEY_A: {
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiBoycoUsdcManager;
    };
  };

  EXTERNAL: {
    WETH_TOKEN: IERC20Metadata;
    WBTC_TOKEN: IERC20Metadata;
    CIRCLE: {
      USDC_TOKEN: IERC20Metadata;
    },
    BERACHAIN: {
      WBERA_TOKEN: IERC20Metadata;
      HONEY_TOKEN: IERC20Metadata;
      BGT_TOKEN: IERC20Metadata;
    },
    GOLDILOCKS: {
      LOCKS_TOKEN: IERC20Metadata;
    },
    YEET: {
      YEET_TOKEN: IERC20Metadata;
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
    LOV_HONEY_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_HONEY_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_HONEY_A.MANAGER, owner),
    },
    LOV_WBERA_LONG_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WBERA_LONG_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_WBERA_LONG_A.MANAGER, owner),
    },
    LOV_YEET_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_YEET_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_YEET_A.MANAGER, owner),
    },
    LOV_WBTC_LONG_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WBTC_LONG_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_WBTC_LONG_A.MANAGER, owner),
    },
    LOV_WETH_LONG_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_WETH_LONG_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_WETH_LONG_A.MANAGER, owner),
    },
    LOV_LOCKS_A: {
      TOKEN: OrigamiLovToken__factory.connect(ADDRS.LOV_LOCKS_A.TOKEN, owner),
      MANAGER: OrigamiTestnetLovTokenManager__factory.connect(ADDRS.LOV_LOCKS_A.MANAGER, owner),
    },
    VAULTS: {
      BOYCO_HONEY_A: {
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.BOYCO_HONEY_A.TOKEN, owner),
        MANAGER: OrigamiBoycoUsdcManager__factory.connect(ADDRS.VAULTS.BOYCO_HONEY_A.MANAGER, owner),
      },
    },
    EXTERNAL: {
      WETH_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.WETH_TOKEN, owner),
      WBTC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.WBTC_TOKEN, owner),
      CIRCLE: {
        USDC_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, owner),
      },
      BERACHAIN: {
        WBERA_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner),
        HONEY_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN, owner),
        BGT_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.BGT_TOKEN, owner),
      },
      GOLDILOCKS: {
        LOCKS_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.GOLDILOCKS.LOCKS_TOKEN, owner),
      },
      YEET: {
        YEET_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.YEET.YEET_TOKEN, owner),
      },
    },
  }
}
