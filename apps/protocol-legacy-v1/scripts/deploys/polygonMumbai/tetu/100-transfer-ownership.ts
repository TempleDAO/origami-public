import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { 
    OrigamiVeTetuProxy__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { getDeployedContracts as tetuDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const TETU_DEPLOYED = tetuDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();

    const veTetuProxy = OrigamiVeTetuProxy__factory.connect(TETU_DEPLOYED.ORIGAMI.TETU.VE_TETU_PROXY, owner);

    // Propose governance change to the timelock
    await mine(veTetuProxy.proposeNewGov(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
