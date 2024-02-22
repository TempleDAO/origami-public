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
    polygon: {
        ORIGAMI: {
            TETU: {
                VE_TETU_PROXY: '0x93a717f2772072f91B4165A7464f6c3c54224632',
                // yarn hardhat verify --network polygon 0x93a717f2772072f91B4165A7464f6c3c54224632 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4
            },
        },
        TETU: {
            VE_TETU: '0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4',
            VE_TETU_REWARDS_DISTRIBUTOR: '0xf8d97eC3a778028E84D4364bCd72bb3E2fb5D18e',
            TETU_VOTER: '0x4cdF28d6244c6B0560aa3eBcFB326e0C24fe8218',
            TETU_PLATFORM_VOTER: '0x5576Fe01a9e6e0346c97E546919F5d15937Be92D',
    
            SNAPSHOT_DELEGATE_REGISTRY: '0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446',
        },
    },
    localhost: {
        ORIGAMI: {
            TETU: {
                VE_TETU_PROXY: '0xf3C8D517ba8462911Cc2b8cfedc5dDeC50DFCBd6',
            },
        },
        TETU: {
            VE_TETU: '0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4',
            VE_TETU_REWARDS_DISTRIBUTOR: '0xf8d97eC3a778028E84D4364bCd72bb3E2fb5D18e',
            TETU_VOTER: '0x4cdF28d6244c6B0560aa3eBcFB326e0C24fe8218',
            TETU_PLATFORM_VOTER: '0x5576Fe01a9e6e0346c97E546919F5d15937Be92D',
    
            SNAPSHOT_DELEGATE_REGISTRY: '0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446',
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
