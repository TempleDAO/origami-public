import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockStEthToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new MockStEthToken__factory(owner);
  await deployAndMine(
    'EXTERNAL.LIDO.STETH_TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.EXTERNAL.STETH_INTEREST_RATE,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });