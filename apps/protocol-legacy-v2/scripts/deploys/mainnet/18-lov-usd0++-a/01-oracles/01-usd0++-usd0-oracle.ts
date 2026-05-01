import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiVolatileCurveEmaOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);

  const factory = new OrigamiVolatileCurveEmaOracle__factory(owner);
  await deployAndMine(
    'ORACLES.USD0pp_USD0',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "USD0++/USD0",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.USUAL.USD0_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.CURVE.USD0pp_USD0_STABLESWAP_NG,
    {
      floor: DEFAULT_SETTINGS.ORACLES.USD0pp_USD0.MIN_THRESHOLD,
      ceiling: DEFAULT_SETTINGS.ORACLES.USD0pp_USD0.MAX_THRESHOLD
    },
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });