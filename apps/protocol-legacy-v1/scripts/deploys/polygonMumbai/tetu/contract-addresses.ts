import { network } from "hardhat";

export interface TetuDeployedContracts {
    ORIGAMI: {
        TETU: {
            VE_TETU_PROXY: string,
        },
    },
    TETU: {
        VE_TETU: string,
        VE_TETU_REWARDS_DISTRIBUTOR: string,
        TETU_VOTER: string,
        TETU_PLATFORM_VOTER: string,

        SNAPSHOT_DELEGATE_REGISTRY: string,
    },
};

const TETU_DEPLOYED_CONTRACTS: {[key: string]: TetuDeployedContracts} = {
    polygonMumbai: {
        ORIGAMI: {
            TETU: {
                VE_TETU_PROXY: '',
            },
        },
        TETU: {
            VE_TETU: '',
            VE_TETU_REWARDS_DISTRIBUTOR: '',
            TETU_VOTER: '',
            TETU_PLATFORM_VOTER: '',
    
            SNAPSHOT_DELEGATE_REGISTRY: '',
        },
    },
}

export function getDeployedContracts(): TetuDeployedContracts {
    if (TETU_DEPLOYED_CONTRACTS[network.name] === undefined) {
      console.log(`No contracts configured for ${network.name}`);
      throw new Error(`No contracts configured for ${network.name}`);
    } else {
      return TETU_DEPLOYED_CONTRACTS[network.name];
    }
}
