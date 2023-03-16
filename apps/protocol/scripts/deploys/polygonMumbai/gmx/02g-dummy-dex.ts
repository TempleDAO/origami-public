import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { DummyDex__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts } from './contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const GMX_DEPLOYED_CONTRACTS = getDeployedContracts();

  const factory = new DummyDex__factory(owner);
  await deployAndMine(
    'Dummy ZeroEx DEX', factory, factory.deploy,
    GMX_DEPLOYED_CONTRACTS.GMX.TOKENS.GMX_TOKEN,
    GMX_DEPLOYED_CONTRACTS.GMX.LIQUIDITY_POOL.WETH_TOKEN,
    ethers.utils.parseUnits("1", 30), // Match the test oracle price. 1 ETH ~= 46.357 GMX
    ethers.utils.parseUnits("46.356982031850672597547879488562", 30),
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