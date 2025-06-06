import '@nomiclabs/hardhat-ethers';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.USD0pp_USDC_FLOOR_PRICE',
    factory,
    factory.deploy,
    {
      description: "USD0++/USDC (floor price)",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.MORPHO.ORACLE.USD0pp_FLOOR_PRICE_ADAPTER,
    0, // No staleness threshold
    false, // Adapter doesn't use roundId
    false  // Adapter doesn't use lastUpdatedAt
  );
}

runAsyncMain(main);
