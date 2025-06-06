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
  const pendleMarketAddress = ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.MARKET;
  const twapSecs = DEFAULT_SETTINGS.ORACLES.PT_LBTC_MAR_2025_LBTC.TWAP_DURATION_SECS;

  // Check the Pendle Oracle and increase the cardinality if required.
  await updatePendleOracleCardinality(pendleOracleAddress, pendleMarketAddress, owner, twapSecs);

  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_LBTC_MAR_2025_LBTC',
    factory,
    factory.deploy,
    {
      description: "PT-LBTC-Mar2025/LBTC",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.LOMBARD.LBTC_TOKEN.decimals(),
    },
    pendleOracleAddress,
    pendleMarketAddress,
    twapSecs,
  );
}

runAsyncMain(main);
