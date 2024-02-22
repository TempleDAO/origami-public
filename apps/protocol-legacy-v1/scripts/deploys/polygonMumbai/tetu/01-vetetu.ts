import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiVeTetuProxy__factory } from '../../../../typechain';
import {
    deployProxyAndMine,
    ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts as tetuDeployedContracts } from './contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const TETU_DEPLOYED_CONTRACTS = tetuDeployedContracts();

    const factory = new OrigamiVeTetuProxy__factory(owner);
    await deployProxyAndMine(
        TETU_DEPLOYED_CONTRACTS.ORIGAMI.TETU.VE_TETU_PROXY,
        'veTetu Proxy', 'uups',
        [
            TETU_DEPLOYED_CONTRACTS.TETU.VE_TETU,
        ],
        factory, factory.deploy,
        await owner.getAddress(),
        TETU_DEPLOYED_CONTRACTS.TETU.VE_TETU_REWARDS_DISTRIBUTOR,
        TETU_DEPLOYED_CONTRACTS.TETU.SNAPSHOT_DELEGATE_REGISTRY,
        TETU_DEPLOYED_CONTRACTS.TETU.TETU_VOTER,
        TETU_DEPLOYED_CONTRACTS.TETU.TETU_PLATFORM_VOTER,
    );
}
        
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
