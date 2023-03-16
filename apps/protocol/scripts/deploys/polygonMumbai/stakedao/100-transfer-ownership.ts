import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { 
    OrigamiVeSDTProxy__factory,
} from '../../../../typechain';
import {
    ensureExpectedEnvvars,
    mine,
} from '../../helpers';
import { getDeployedContracts as stakedaoDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

async function main() {
    ensureExpectedEnvvars();
    const [owner] = await ethers.getSigners();
    const STAKEDAO_DEPLOYED = stakedaoDeployedContracts();
    const GOV_DEPLOYED = govDeployedContracts();

    const veSdtProxy = OrigamiVeSDTProxy__factory.connect(STAKEDAO_DEPLOYED.ORIGAMI.STAKEDAO.VE_SDT_PROXY, owner);

    // Propose governance change to the timelock
    await mine(veSdtProxy.proposeNewGov(GOV_DEPLOYED.ORIGAMI.GOV_TIMELOCK));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
