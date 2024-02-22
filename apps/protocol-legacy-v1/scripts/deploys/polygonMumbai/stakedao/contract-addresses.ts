import { network } from "hardhat";

export interface StakeDaoDeployedContracts {
    ORIGAMI: {
        STAKEDAO: {
            VE_SDT_PROXY: string,
        },
    },
    STAKEDAO: {
        VE_SDT: string,
        SDT: string,
        VE_SDT_REWARDS_DISTRIBUTOR: string,
        VE_SDT_GAUGE_REWARDS_CLAIMER: string,

        SDT_LOCKER_GAUGE_CONTROLLER: string, 
        SDT_STRATEGY_GAUGE_CONTROLLER: string,

        SNAPSHOT_DELEGATE_REGISTRY: string,
        VE_BOOST: string,
    },
};

const STAKEDAO_DEPLOYED_CONTRACTS: {[key: string]: StakeDaoDeployedContracts} = {
    polygonMumbai: {
        ORIGAMI: {
            STAKEDAO: {
                VE_SDT_PROXY: '',
            },
        },
        STAKEDAO: {
            VE_SDT: '',
            SDT: '',
            VE_SDT_REWARDS_DISTRIBUTOR: '',
            VE_SDT_GAUGE_REWARDS_CLAIMER: '',

            SDT_LOCKER_GAUGE_CONTROLLER: '', 
            SDT_STRATEGY_GAUGE_CONTROLLER: '',

            SNAPSHOT_DELEGATE_REGISTRY: '',
            VE_BOOST: '',
        },
    },
}

export function getDeployedContracts(): StakeDaoDeployedContracts {
    if (STAKEDAO_DEPLOYED_CONTRACTS[network.name] === undefined) {
      console.log(`No contracts configured for ${network.name}`);
      throw new Error(`No contracts configured for ${network.name}`);
    } else {
      return STAKEDAO_DEPLOYED_CONTRACTS[network.name];
    }
}
