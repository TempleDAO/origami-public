import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockFlashLoanProvider__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new MockFlashLoanProvider__factory(owner);
  await deployAndMine(
    'CORE.SPARK_FLASH_LOAN_PROVIDER',
    factory,
    factory.deploy
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });