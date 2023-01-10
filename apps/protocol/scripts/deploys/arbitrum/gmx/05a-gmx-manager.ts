import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { ZERO_ADDRESS } from '../../../../test/helpers';
import { OrigamiGmxManager__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new OrigamiGmxManager__factory(owner);
  await deployAndMine(
    'origamiGmxManager', factory, factory.deploy,
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GMX_REWARD_ROUTER, 
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GLP_REWARD_ROUTER, 
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.oGMX,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.oGLP,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.MULTISIG,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_EARN_ACCOUNT,
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