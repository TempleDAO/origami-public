import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { TokenPrices__factory } from '../../../../../typechain';
import { deployAndMine, ensureExpectedEnvvars } from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new TokenPrices__factory(owner);
  await deployAndMine(
    'CORE.TOKEN_PRICES', 
    factory, 
    factory.deploy,
    30
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });