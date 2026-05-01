import '@nomiclabs/hardhat-ethers';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Mar2025-DISCOUNT-TO-MATURITY",
      baseAssetAddress: ZERO_ADDRESS,
      baseAssetDecimals: 18,
      quoteAssetAddress: ZERO_ADDRESS,
      quoteAssetDecimals: 18,
    },
    ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.DISCOUNT_TO_MATURITY_ORACLE,
    0,
    false, // Not used
    false  // Not used
  );
}

runAsyncMain(main);