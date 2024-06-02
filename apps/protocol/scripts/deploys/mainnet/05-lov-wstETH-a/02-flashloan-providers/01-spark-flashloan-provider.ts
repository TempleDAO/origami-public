import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiAaveV3FlashLoanProvider__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiAaveV3FlashLoanProvider__factory(owner);
  await deployAndMine(
    'FLASHLOAN_PROVIDERS.SPARK',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });