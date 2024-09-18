import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { DummyMintableToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new DummyMintableToken__factory(owner);
  await deployAndMine(
    'EXTERNAL.SKY.SDAO_TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    "SDAO",
    "SDAO",
    18,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });