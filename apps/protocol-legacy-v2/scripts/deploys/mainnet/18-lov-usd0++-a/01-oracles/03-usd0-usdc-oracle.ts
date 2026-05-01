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
    'ORACLES.USD0_USDC',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "USD0/USDC",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.CURVE.USD0_USDC_STABLESWAP_NG,
    {
      floor: DEFAULT_SETTINGS.ORACLES.USD0_USDC.MIN_THRESHOLD,
      ceiling: DEFAULT_SETTINGS.ORACLES.USD0_USDC.MAX_THRESHOLD
    },
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });