import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { Morpho__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new Morpho__factory(owner);
  await deployAndMine(
    'EXTERNAL.MORPHO.SINGLETON',
    factory,
    factory.deploy,
    await owner.getAddress(),
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });