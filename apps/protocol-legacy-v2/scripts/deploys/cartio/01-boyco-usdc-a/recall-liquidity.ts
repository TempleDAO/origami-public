
import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const lpBalance = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.lpBalanceStaked();
  const inputs = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.callStatic.recallLiquidityQuote(
    lpBalance,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    100 // bps
  );

  console.log(inputs);

  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.recallLiquidity(
    lpBalance,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    inputs.requestData
  ));
}

runAsyncMain(main);
