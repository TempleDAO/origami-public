import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { IPMarket__factory, OrigamiPendlePtToAssetOracle__factory, PendlePYLpOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  mine,
  updatePendleOracleCardinality,
} from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);

  const pendleOracleAddress = ADDRS.EXTERNAL.PENDLE.ORACLE;
  const pendleMarketAddress = ADDRS.EXTERNAL.PENDLE.CORN_LBTC_DEC24.MARKET;
  const twapSecs = DEFAULT_SETTINGS.ORACLES.PT_CORN_LBTC_DEC24_LBTC.TWAP_DURATION_SECS;

  // Check the Pendle Oracle and increase the cardinality if required.
  await updatePendleOracleCardinality(pendleOracleAddress, pendleMarketAddress, owner, twapSecs);

  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_CORN_LBTC_DEC24_LBTC',
    factory,
    factory.deploy,
    {
      description: "PT-cornLBTC-Dec24/LBTC",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.CORN_LBTC_DEC24.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.CORN_LBTC_DEC24.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.LOMBARD.LBTC_TOKEN.decimals(),
    },
    pendleOracleAddress,
    pendleMarketAddress,
    twapSecs,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });