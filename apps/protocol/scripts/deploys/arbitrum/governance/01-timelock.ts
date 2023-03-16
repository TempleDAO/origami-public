import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { TimelockController__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts } from './contract-addresses';
import { ZERO_ADDRESS } from '../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GOV_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new TimelockController__factory(owner);
  await deployAndMine(
    'timelockController', factory, factory.deploy,
    18*60*60, // 18 hours
    [GOV_DEPLOYED_CONTRACTS.ORIGAMI.MULTISIG],
    [GOV_DEPLOYED_CONTRACTS.ORIGAMI.MULTISIG],
    ZERO_ADDRESS,
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