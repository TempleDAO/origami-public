import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockWrappedEther__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new MockWrappedEther__factory(owner);
  await deployAndMine(
    'EXTERNAL.WETH_TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress()
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });