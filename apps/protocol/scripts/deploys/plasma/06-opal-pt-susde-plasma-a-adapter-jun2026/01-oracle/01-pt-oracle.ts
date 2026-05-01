import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import { IERC20Metadata__factory, OrigamiPendlePtToAssetOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
  updatePendleOracleCardinality,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const name = 'ORACLES.PT_SUSDE_18JUN2026_USDE';
  const PENDLE_ADDRS = ADDRS.EXTERNAL.PENDLE.SUSDE_18JUN2026;
  const UNDERLYING_ADDR = ADDRS.EXTERNAL.ETHENA.USDE_TOKEN; // PT-sUSDe redeems to USDe
  const TWAP_DURATION = DEFAULT_SETTINGS.ORACLES.PT_SUSDE_18JUN2026_USDE.TWAP_DURATION_SECS;
  const pendleOracleAddress = ADDRS.EXTERNAL.PENDLE.ORACLE;

  // Only use 15mins in localhost since we move forward in time and the Chainlink
  // oracles will become stale if too long
  const twapSecs = network.name === "localhost" ? 900 : TWAP_DURATION;

  // Check the Pendle Oracle and increase the cardinality if required.
  await updatePendleOracleCardinality(pendleOracleAddress, PENDLE_ADDRS.MARKET, owner, twapSecs);

  const base = IERC20Metadata__factory.connect(PENDLE_ADDRS.PT_TOKEN, owner);
  const quote = IERC20Metadata__factory.connect(UNDERLYING_ADDR, owner);
  const factory = new OrigamiPendlePtToAssetOracle__factory(owner);
  await deployAndMine(
    name,
    factory,
    factory.deploy,
    {
      description: `${await base.symbol()}/${await quote.symbol()}`,
      baseAssetAddress: base.address,
      baseAssetDecimals: await base.decimals(),
      quoteAssetAddress: quote.address,
      quoteAssetDecimals: await quote.decimals(),
    },
    pendleOracleAddress,
    PENDLE_ADDRS.MARKET,
    twapSecs,
  );
}

runAsyncMain(main);
