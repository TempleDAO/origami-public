import '@nomiclabs/hardhat-ethers';
import { BigNumber } from 'ethers';
import { ethers, network } from 'hardhat';
import { DummyUniV3Pool__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import {getDeployedContracts} from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts(network.name);

  const factory = new DummyUniV3Pool__factory(owner);
  
  // ETH/GMX = ~46.35
  // $GMX == 2000 / 46.35 == 43.14
  await deployAndMine(
    'ethGmxUniV3', factory, factory.deploy,
    BigNumber.from("46356982031850672597547879488562"),
    GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN,
    GMX_DEPLOYED_CONTRACTS.GMX.TOKENS.GMX_TOKEN,
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