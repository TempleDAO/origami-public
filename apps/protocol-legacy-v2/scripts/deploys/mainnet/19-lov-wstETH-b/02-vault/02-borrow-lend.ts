import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiAaveV3BorrowAndLend__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);

  const factory = new OrigamiAaveV3BorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_WSTETH_B.SPARK_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    await INSTANCES.EXTERNAL.AAVE.V3_LIDO_POOL_ADDRESS_PROVIDER.getPool(),
    DEFAULT_SETTINGS.EXTERNAL.AAVE.EMODES.ETH,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });