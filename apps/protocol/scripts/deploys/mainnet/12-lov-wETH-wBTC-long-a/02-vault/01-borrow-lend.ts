import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiAaveV3BorrowAndLend__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const factory = new OrigamiAaveV3BorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_WETH_WBTC_LONG_A.SPARK_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.WBTC_TOKEN,
    await INSTANCES.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER.getPool(),
    DEFAULT_SETTINGS.EXTERNAL.SPARK.EMODES.DEFAULT
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });