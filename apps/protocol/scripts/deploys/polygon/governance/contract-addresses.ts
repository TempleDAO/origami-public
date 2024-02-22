import { network } from "hardhat";

export interface GovernanceDeployedContracts {
    ORIGAMI: {
        MULTISIG: string,
        GOV_TIMELOCK: string,
    },
};

const GOV_DEPLOYED_CONTRACTS: {[key: string]: GovernanceDeployedContracts} = {
    polygon: {
        ORIGAMI: {
            MULTISIG: '0xF6C623d4d7443F72469790796Ea1108ED5Af81B6',

            GOV_TIMELOCK: '0xeF0c2c5221421bc1a01C4828b17Df94f5A485185',
            // yarn hardhat verify --network polygon 0xeF0c2c5221421bc1a01C4828b17Df94f5A485185 --constructor-args arguments.js
            // module.exports = [
            //     64800,
            //     [
            //         '0xF6C623d4d7443F72469790796Ea1108ED5Af81B6'
            //     ],
            //     [
            //         '0xF6C623d4d7443F72469790796Ea1108ED5Af81B6',
            //     ],
            //     '0x0000000000000000000000000000000000000000',
            //   ];
        },
    },
    localhost: {
        ORIGAMI: {
            MULTISIG: '0xA7F0F04efB55eaEfBC4649C523F7a773f91D5526',
            GOV_TIMELOCK: '0x64A11d414D66819e17e8Cbe6A37E7Fd90021C890',
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
