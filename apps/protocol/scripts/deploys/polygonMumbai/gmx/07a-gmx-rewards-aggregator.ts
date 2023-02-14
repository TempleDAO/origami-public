import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiGmxRewardsAggregator__factory } from '../../../../typechain';
import {
  GmxVaultType,
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new OrigamiGmxRewardsAggregator__factory(owner);
  await deployAndMine(
    'origamiGmxRewardsAggregator', factory, factory.deploy,
    GmxVaultType.GMX,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_MANAGER,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_MANAGER,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.ovGMX,
    GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN,
    GMX_DEPLOYED_CONTRACTS.ZERO_EX_PROXY,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.MULTISIG,
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