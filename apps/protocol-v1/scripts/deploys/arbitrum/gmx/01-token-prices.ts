import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { TokenPrices__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new TokenPrices__factory(owner);
  await deployAndMine(
    'tokenPrices', factory, factory.deploy,
    30
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