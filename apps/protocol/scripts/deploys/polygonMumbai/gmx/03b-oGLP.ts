import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiGlpInvestment__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts(network.name);

  const factory = new OrigamiGlpInvestment__factory(owner);
  await deployAndMine(
    'oGLP', factory, factory.deploy,
    await owner.getAddress(),
    GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN,
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