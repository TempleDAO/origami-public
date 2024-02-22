import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiGmxEarnAccount__factory } from '../../../../typechain';
import {
  deployProxyAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts(network.name);

  const factory = new OrigamiGmxEarnAccount__factory(owner);
  await deployProxyAndMine(
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_PRIMARY_EARN_ACCOUNT,
    'origamiGlpPrimaryEarnAccount', 'uups', 
    [GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GMX_REWARD_ROUTER],
    factory, factory.deploy,
    await owner.getAddress(),
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GMX_REWARD_ROUTER, 
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GLP_REWARD_ROUTER, 
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.GLP_ESGMX_VESTER,
    GMX_DEPLOYED_CONTRACTS.GMX.STAKING.STAKED_GLP,
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