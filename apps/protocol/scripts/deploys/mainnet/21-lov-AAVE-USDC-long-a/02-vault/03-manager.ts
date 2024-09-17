import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenFlashAndBorrowManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiLovTokenFlashAndBorrowManager__factory(owner);
  await deployAndMine(
    'LOV_AAVE_USDC_LONG_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.AAVE.AAVE_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.AAVE.AAVE_TOKEN,
    ADDRS.LOV_AAVE_USDC_LONG_A.TOKEN,
    ADDRS.FLASHLOAN_PROVIDERS.SPARK,
    ADDRS.LOV_AAVE_USDC_LONG_A.SPARK_BORROW_LEND
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });