import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { DummyLovTokenSwapper__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new DummyLovTokenSwapper__factory(owner);
  await deployAndMine(
    'CORE.SWAPPER_1INCH',
    factory,
    factory.deploy,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });