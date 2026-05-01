import { network } from "hardhat";
import {
  TokenPrices, TokenPrices__factory,
  OrigamiCowSwapper, OrigamiCowSwapper__factory,
  DummyMintableToken, DummyMintableToken__factory,
  OrigamiDelegated4626Vault,
  OrigamiDelegated4626Vault__factory,
  OrigamiSuperSavingsUsdsManager,
  OrigamiSuperSavingsUsdsManager__factory,
  MockSDaiToken,
  MockSDaiToken__factory,
  DummySkyStakingRewards,
  DummySkyStakingRewards__factory,
  OrigamiHOhmVault,
  OrigamiHOhmManager,
  DummyDexRouter,
  OrigamiSwapperWithCallback,
  IERC20Metadata,
  IMonoCooler,
  IERC20Metadata__factory,
  IMonoCooler__factory,
  OrigamiHOhmVault__factory,
  OrigamiHOhmManager__factory,
  DummyDexRouter__factory,
  OrigamiSwapperWithCallback__factory,
  OrigamiTokenTeleporter,
  OrigamiTokenTeleporter__factory,
} from "../../../../typechain";
import { Signer } from "ethers";
import { ContractAddresses } from "./types";
import { CONTRACTS as HOLESKY_CONTRACTS } from "./holesky";

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "holesky" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'holesky' || network.name === 'localhost') {
    return HOLESKY_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'holesky') {
    return HOLESKY_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(HOLESKY_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  CORE: {
    TOKEN_PRICES: {
      V3: TokenPrices;
      V4: TokenPrices;
    };
  };

  VAULTS: {
    SUSDSpS: {
      TOKEN: OrigamiDelegated4626Vault;
      MANAGER: OrigamiSuperSavingsUsdsManager;
      COW_SWAPPER: OrigamiCowSwapper;
    };
    hOHM: {
      TOKEN: OrigamiHOhmVault;
      MANAGER: OrigamiHOhmManager;
      DUMMY_DEX_ROUTER: DummyDexRouter;
      SWEEP_SWAPPER: OrigamiSwapperWithCallback;
      TELEPORTER: OrigamiTokenTeleporter;
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
    };
    OLYMPUS: {
      GOHM_TOKEN: IERC20Metadata;
      MONO_COOLER: IMonoCooler;
    };
  };
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    CORE: {
      TOKEN_PRICES: {
          V3: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V3, owner),
          V4: TokenPrices__factory.connect(ADDRS.CORE.TOKEN_PRICES.V4, owner),
        },
    },
    VAULTS: {
      SUSDSpS: {
        TOKEN: OrigamiDelegated4626Vault__factory.connect(ADDRS.VAULTS.SUSDSpS.TOKEN, owner),
        MANAGER: OrigamiSuperSavingsUsdsManager__factory.connect(ADDRS.VAULTS.SUSDSpS.MANAGER, owner),
        COW_SWAPPER: OrigamiCowSwapper__factory.connect(ADDRS.VAULTS.SUSDSpS.COW_SWAPPER, owner),
      },
      hOHM: {
        TOKEN: OrigamiHOhmVault__factory.connect(ADDRS.VAULTS.hOHM.TOKEN, owner),
        MANAGER: OrigamiHOhmManager__factory.connect(ADDRS.VAULTS.hOHM.MANAGER, owner),
        DUMMY_DEX_ROUTER: DummyDexRouter__factory.connect(ADDRS.VAULTS.hOHM.DUMMY_DEX_ROUTER, owner),
        SWEEP_SWAPPER: OrigamiSwapperWithCallback__factory.connect(ADDRS.VAULTS.hOHM.SWEEP_SWAPPER, owner),
        TELEPORTER: OrigamiTokenTeleporter__factory.connect(ADDRS.VAULTS.hOHM.TELEPORTER, owner),
      }
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
      OLYMPUS: {
        GOHM_TOKEN: IERC20Metadata__factory.connect(ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN, owner),
        MONO_COOLER: IMonoCooler__factory.connect(ADDRS.EXTERNAL.OLYMPUS.MONO_COOLER, owner),
      },
    },
  }
}
