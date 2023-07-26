import { network } from "hardhat";

export interface GovernanceDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,
        FEE_COLLECTOR: string,
        GOV_TIMELOCK: string,
    },
};

const GOV_DEPLOYED_CONTRACTS: {[key: string]: GovernanceDeployedContracts} = {
    arbitrum: {
        ORIGAMI: {
            MULTISIG: '0x2eb2717755E6A82762D439e15d4ef1E5Ced6bA35',
            FEE_COLLECTOR: '0x2eb2717755E6A82762D439e15d4ef1E5Ced6bA35',
            GOV_TIMELOCK: '0x85A6026bc75A11b77A3A0584aA33ECD98C40BDFb',
        },
    },
    avalanche: {
        ORIGAMI: {
            MULTISIG: '',
            FEE_COLLECTOR: '',
            GOV_TIMELOCK: '',
        }
    },
    localhost: {
        ORIGAMI: {
            MULTISIG: '0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526',
            FEE_COLLECTOR: '0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526',
            GOV_TIMELOCK: '0xf5059a5D33d5853360D16C683c16e67980206f36',
        },
    },
}

export function getDeployedContracts(): GovernanceDeployedContracts {
    if (GOV_DEPLOYED_CONTRACTS[network.name] === undefined) {
      console.log(`No contracts configured for ${network.name}`);
      throw new Error(`No contracts configured for ${network.name}`);
    } else {
      return GOV_DEPLOYED_CONTRACTS[network.name];
    }
}
