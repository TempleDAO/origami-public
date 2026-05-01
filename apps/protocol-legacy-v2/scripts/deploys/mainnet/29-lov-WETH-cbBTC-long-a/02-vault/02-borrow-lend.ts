import '@nomiclabs/hardhat-ethers';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { OrigamiAaveV3BorrowAndLend__factory } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiAaveV3BorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN,
    await INSTANCES.EXTERNAL.AAVE.V3_MAINNET_POOL_ADDRESS_PROVIDER.getPool(),
    DEFAULT_SETTINGS.EXTERNAL.AAVE.EMODES.DEFAULT,
  );
}

runAsyncMain(main);
