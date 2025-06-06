import '@nomiclabs/hardhat-ethers';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiCrossRateOracle__factory(owner);

  /*
    USD0++/USDC [floor price] * conversionOracle = USD0++/USDC [market price]
    conversionOracle = USD0++/USDC [market price] / USD0++/USDC [floor price]
   */
  await deployAndMine(
    'ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION',
    factory,
    factory.deploy,
    {
      description: "USD0++/USDC Morpho to Market conversion",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
    },
    ADDRS.ORACLES.USD0pp_USDC_MARKET_PRICE,
    ADDRS.ORACLES.USD0pp_USDC_FLOOR_PRICE,
    ZERO_ADDRESS
  );
}

runAsyncMain(main);