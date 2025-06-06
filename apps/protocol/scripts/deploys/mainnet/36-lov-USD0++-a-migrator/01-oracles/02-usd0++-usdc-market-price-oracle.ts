import '@nomiclabs/hardhat-ethers';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.USD0pp_USDC_MARKET_PRICE',
    factory,
    factory.deploy,
    {
      description: "USD0++/USDC (market price)",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.CHAINLINK.USD0pp_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USD0pp_USD_ORACLE.STALENESS_THRESHOLD,
    true,
    true
  );
}

runAsyncMain(main);
