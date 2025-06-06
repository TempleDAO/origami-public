import '@nomiclabs/hardhat-ethers';
import { OrigamiPendlePtToAssetOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
  updatePendleOracleCardinality,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const pendleOracleAddress = ADDRS.EXTERNAL.PENDLE.ORACLE;
  const pendleMarketAddress = ADDRS.EXTERNAL.PENDLE.USD0pp_MAR_2025.MARKET;
  const twapSecs = DEFAULT_SETTINGS.ORACLES.PT_USD0pp_MAR_2025_USDC.TWAP_DURATION_SECS;

  // Check the Pendle Oracle and increase the cardinality if required.
  await updatePendleOracleCardinality(pendleOracleAddress, pendleMarketAddress, owner, twapSecs);

  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_USD0pp_MAR_2025_USD0pp',
    factory,
    factory.deploy,
    {
      description: "PT-USD0++-Mar2025/USD0pp",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
    },
    pendleOracleAddress,
    pendleMarketAddress,
    twapSecs,
  );
}

runAsyncMain(main);
