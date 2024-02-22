import { network } from "hardhat";

export interface GovernanceDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,
    },
};

const GOV_DEPLOYED_CONTRACTS: {[key: string]: GovernanceDeployedContracts} = {
    mainnet: {
        ORIGAMI: {
            MULTISIG: '',
        },
    },
    localhost: {
        ORIGAMI: {
            MULTISIG: '0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526',
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
