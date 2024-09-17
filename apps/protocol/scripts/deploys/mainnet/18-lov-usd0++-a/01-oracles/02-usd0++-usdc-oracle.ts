import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiFixedPriceOracle__factory, OrigamiStableChainlinkOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiFixedPriceOracle__factory(owner);
  await deployAndMine(
    'ORACLES.USD0pp_USDC',
    factory,
    factory.deploy,
    {
      description: "USD0++/USDC",
      baseAssetAddress: ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.USUAL.USD0pp_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.decimals(),
    },
    DEFAULT_SETTINGS.ORACLES.USD0pp_USDC.FIXED_PRICE,
    ADDRS.ORACLES.USD0pp_USD0,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });