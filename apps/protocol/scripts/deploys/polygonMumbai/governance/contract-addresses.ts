import { network } from "hardhat";

export interface GovernanceDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,
        FEE_COLLECTOR: string,
        GOV_TIMELOCK: string,
    },
};

const GMX_DEPLOYED_CONTRACTS: {[key: string]: GovernanceDeployedContracts} = {
    polygonMumbai: {
        ORIGAMI: {
            // A hot wallet, Mumbai isn't in Gnosis - ask @frontier for the PK if required.
            MULTISIG: '0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165',
            
            // Same as the msig
            FEE_COLLECTOR: '0x69E5F7487090EeFd92c16A803b3e6a689d8Ec165',

            GOV_TIMELOCK: '0xFbC75D816E1B7DaAa0B5FF0b3e08299757ED2696',
            // yarn hardhat verify --network polygonMumbai 0xFbC75D816E1B7DaAa0B5FF0b3e08299757ED2696 --constructor-args arguments.js
        }
    },
}

export function getDeployedContracts(): GovernanceDeployedContracts {
    if (GMX_DEPLOYED_CONTRACTS[network.name] === undefined) {
      console.log(`No contracts configured for ${network.name}`);
      throw new Error(`No contracts configured for ${network.name}`);
    } else {
      return GMX_DEPLOYED_CONTRACTS[network.name];
    }
}
