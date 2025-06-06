import '@nomiclabs/hardhat-ethers';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_USD0pp_MAR_2025_USDC_PEGGED',
    factory,
    factory.deploy,
    {
      description: "PT-USD0++-Mar2025/USDC",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
    },
    ADDRS.ORACLES.PT_USD0pp_MAR_2025_USD0pp,
    ADDRS.ORACLES.USD0pp_USDC_PEGGED, // This reverts if USD0pp/USD0 curve EMA depegs
    ADDRS.ORACLES.USD0_USDC,   // This reverts if USD0/USDC curve EMA depegs
  );
}

runAsyncMain(main);