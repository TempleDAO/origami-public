import { network } from 'hardhat';
import {
  OrigamiOFT,
  OrigamiOFT__factory,
} from '../../../../typechain';
import { Signer } from 'ethers';
import { ContractAddresses } from './types';
import { CONTRACTS as BEPOLIA_CONTRACTS } from './bepolia';

// dirname is expected to be the path of the hardhat deploy script
// This will crudely search for the `scripts/${dir}/address-overrides.ts` module
// and apply the overrides to addrs
async function applyOverrides(addrs: ContractAddresses, dirname: string) {
  const dirs = dirname.split("/");
  let scriptDir = "";
  for (let i = dirs.length-1; i >= 0; i--) {
    if (dirs[i] == "bepolia" || dirs[i] == "scripts") {
      scriptDir = dirs[i+1];
      break;
    }
  }

  const module = await import(`../scripts/${scriptDir}/address-overrides`);
  return module.applyOverrides(addrs);
}

export function getDeployedContracts(): ContractAddresses {
  if (network.name === 'bepolia') {
    return BEPOLIA_CONTRACTS;
  } else if (network.name === 'localhost') {
    return BEPOLIA_CONTRACTS;
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export async function getDeployedContracts1(
  applyOverridesPath: string
): Promise<ContractAddresses> {
  if (network.name === 'bepolia') {
    return BEPOLIA_CONTRACTS;
  } else if (network.name === 'localhost') {
    return await applyOverrides(BEPOLIA_CONTRACTS, applyOverridesPath);
  }
  console.log(`No contracts configured for ${network.name}`);
  throw new Error(`No contracts configured for ${network.name}`);
}

export interface ContractInstances {
  VAULTS: {
    hOHM: {
      TOKEN: OrigamiOFT;
    }
  }
}

export function connectToContracts(owner: Signer): ContractInstances {
  return connectToContracts1(owner, getDeployedContracts());
}

export function connectToContracts1(owner: Signer, ADDRS: ContractAddresses): ContractInstances {
  return {
    VAULTS: {
      hOHM: {
        TOKEN: OrigamiOFT__factory.connect(ADDRS.VAULTS.hOHM.TOKEN, owner),
      }
    }
  }
}