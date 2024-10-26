import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  OrigamiCowSwapper, OrigamiCowSwapper__factory,
  DummyMintableToken, DummyMintableToken__factory,
  OrigamiSuperSavingsUsdsVault,
  OrigamiSuperSavingsUsdsManager,
  OrigamiSuperSavingsUsdsVault__factory,
  OrigamiSuperSavingsUsdsManager__factory,
  MockSDaiToken,
  MockSDaiToken__factory,
  DummySkyStakingRewards,
  DummySkyStakingRewards__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as SEPOLIA_CONTRACTS } from "./sepolia";
// import { CONTRACTS as LOCALHOST_CONTRACTS } from "./localhost";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "mainnet" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'sepolia') {
    return SEPOLIA_CONTRACTS;
  // } else if (network.name === 'localhost') {
  //   return LOCALHOST_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'sepolia') {
    return SEPOLIA_CONTRACTS;
  // } else if (network.name === 'localhost') {
  //   return await applyOverrides(MAINNET_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V3: TokenPrices;
    },
  },

  VAULTS: {
    SUSDSpS: {
      TOKEN: OrigamiSuperSavingsUsdsVault;
      MANAGER: OrigamiSuperSavingsUsdsManager;
      COW_SWAPPER: OrigamiCowSwapper;
    };
  };
  
  EXTERNAL: {
    SKY: {
      USDS_TOKEN: DummyMintableToken;
      SUSDS_TOKEN: MockSDaiToken;
      SKY_TOKEN: DummyMintableToken;
      SDAO_TOKEN: DummyMintableToken;
      STAKING_FARMS: {
        USDS_SKY: DummySkyStakingRewards;
        USDS_SDAO: DummySkyStakingRewards;
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
      SUSDSpS: {
        TOKEN: OrigamiSuperSavingsUsdsVault__factory.connect(ADDRS.VAULTS.SUSDSpS.TOKEN, owner),
        MANAGER: OrigamiSuperSavingsUsdsManager__factory.connect(ADDRS.VAULTS.SUSDSpS.MANAGER, owner),
        COW_SWAPPER: OrigamiCowSwapper__factory.connect(ADDRS.VAULTS.SUSDSpS.COW_SWAPPER, owner),
      },
    },
    EXTERNAL: {
      SKY: {
        USDS_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.SKY.USDS_TOKEN, owner),
        SUSDS_TOKEN: MockSDaiToken__factory.connect(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN, owner),
        SKY_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.SKY.SKY_TOKEN, owner),
        SDAO_TOKEN: DummyMintableToken__factory.connect(ADDRS.EXTERNAL.SKY.SDAO_TOKEN, owner),
        STAKING_FARMS: {
          USDS_SKY: DummySkyStakingRewards__factory.connect(ADDRS.EXTERNAL.SKY.STAKING_FARMS.USDS_SKY, owner),
          USDS_SDAO: DummySkyStakingRewards__factory.connect(ADDRS.EXTERNAL.SKY.STAKING_FARMS.USDS_SDAO, owner),
        },
      },
    },
  }
}
