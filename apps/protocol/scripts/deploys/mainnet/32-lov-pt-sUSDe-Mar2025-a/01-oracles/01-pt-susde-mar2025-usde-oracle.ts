import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
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
  const pendleMarketAddress = ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.MARKET;

  // Only use 15mins in localhost since we move forward in time and the Chainlink
  // oracles will become stale if too long
  const twapSecs = network.name === "localhost" ? 900 : DEFAULT_SETTINGS.ORACLES.PT_SUSDE_MAR_2025_SUSDE.TWAP_DURATION_SECS;

  // Check the Pendle Oracle and increase the cardinality if required.
  await updatePendleOracleCardinality(pendleOracleAddress, pendleMarketAddress, owner, twapSecs);

  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_MAR_2025_USDE',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Mar2025/USDe",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.decimals(),
    },
    pendleOracleAddress,
    pendleMarketAddress,
    twapSecs,
  );
}

runAsyncMain(main);
