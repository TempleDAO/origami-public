import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiDexAggregatorSwapper__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiDexAggregatorSwapper__factory(owner);
  await deployAndMine(
    'SWAPPERS.DIRECT_1INCH_SWAPPER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.ONE_INCH.ROUTER_V6,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });