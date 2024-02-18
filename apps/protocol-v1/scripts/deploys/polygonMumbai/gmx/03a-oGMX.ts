import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiGmxInvestment__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new OrigamiGmxInvestment__factory(owner);
  await deployAndMine(
    'oGMX', factory, factory.deploy, await owner.getAddress(),
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