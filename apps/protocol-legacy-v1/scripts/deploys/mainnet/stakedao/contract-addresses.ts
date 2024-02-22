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
    mainnet: {
        ORIGAMI: {
            STAKEDAO: {
                VE_SDT_PROXY: '',
            },
        },
        STAKEDAO: {
            VE_SDT: '0x0C30476f66034E11782938DF8e4384970B6c9e8a',
            SDT: '0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F',
            VE_SDT_REWARDS_DISTRIBUTOR: '0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92',
            VE_SDT_GAUGE_REWARDS_CLAIMER: '0x633120100e108F03aCe79d6C78Aac9a56db1be0F',

            SDT_LOCKER_GAUGE_CONTROLLER: '0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882', 
            SDT_STRATEGY_GAUGE_CONTROLLER: '0x3F3F0776D411eb97Cfa4E3eb25F33c01ca4e7Ca8',

            SNAPSHOT_DELEGATE_REGISTRY: '0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446',
            VE_BOOST: '0x47B3262C96BB55A8D2E4F8E3Fed29D2eAB6dB6e9',
        },
    },
    localhost: {
        ORIGAMI: {
            STAKEDAO: {
                VE_SDT_PROXY: '0xF85895D097B2C25946BB95C4d11E2F3c035F8f0C',
            },
        },
        STAKEDAO: {
            VE_SDT: '0x0C30476f66034E11782938DF8e4384970B6c9e8a',
            SDT: '0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F',
            VE_SDT_REWARDS_DISTRIBUTOR: '0x29f3dd38dB24d3935CF1bf841e6b2B461A3E5D92',
            VE_SDT_GAUGE_REWARDS_CLAIMER: '0x633120100e108F03aCe79d6C78Aac9a56db1be0F',

            SDT_LOCKER_GAUGE_CONTROLLER: '0x75f8f7fa4b6DA6De9F4fE972c811b778cefce882', 
            SDT_STRATEGY_GAUGE_CONTROLLER: '0x3F3F0776D411eb97Cfa4E3eb25F33c01ca4e7Ca8',

            SNAPSHOT_DELEGATE_REGISTRY: '0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446',
            VE_BOOST: '0x47B3262C96BB55A8D2E4F8E3Fed29D2eAB6dB6e9',
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
