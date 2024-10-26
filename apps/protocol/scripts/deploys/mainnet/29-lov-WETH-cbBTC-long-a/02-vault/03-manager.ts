import '@nomiclabs/hardhat-ethers';
import { OrigamiLovTokenFlashAndBorrowManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  ensureExpectedEnvvars();
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiLovTokenFlashAndBorrowManager__factory(owner);
  await deployAndMine(
    'LOV_WETH_CBBTC_LONG_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN,
    ADDRS.FLASHLOAN_PROVIDERS.SPARK, // Use Spark for zero fees
    ADDRS.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND
  );
}

runAsyncMain(main);
