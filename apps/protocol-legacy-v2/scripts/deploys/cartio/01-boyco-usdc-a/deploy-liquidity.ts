
import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const usdcBalance = await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.balanceOf(ADDRS.VAULTS.BOYCO_USDC_A.MANAGER);
  const inputs = await INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.callStatic.deployLiquidityQuote(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    usdcBalance,
    100 // bps
  );

  console.log(inputs);

  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.deployLiquidity(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    usdcBalance,
    inputs.requestData
  ));
}

runAsyncMain(main);
