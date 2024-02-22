import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiGmxRewardsAggregator__factory } from '../../../../typechain';
import {
  GmxVaultType,
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts as gmxDeployedContracts } from './contract-addresses';
import { getDeployedContracts as govDeployedContracts } from '../governance/contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = gmxDeployedContracts(network.name);
  const GOV_DEPLOYED_CONTRACTS = govDeployedContracts();

  const factory = new OrigamiGmxRewardsAggregator__factory(owner);
  await deployAndMine(
    'origamiGlpRewardsAggregator', factory, factory.deploy,
    await owner.getAddress(),
    GmxVaultType.GLP,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GMX_MANAGER,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.GLP_MANAGER,
    GMX_DEPLOYED_CONTRACTS.ORIGAMI.GMX.ovGLP,
    GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN,
    GMX_DEPLOYED_CONTRACTS.ZERO_EX_PROXY,
    GOV_DEPLOYED_CONTRACTS.ORIGAMI.FEE_COLLECTOR,
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