import '@nomiclabs/hardhat-ethers';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_MAR_2025_DAI',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Mar2025/DAI",
      baseAssetAddress: ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.decimals(),
    },
    ADDRS.ORACLES.PT_SUSDE_MAR_2025_USDE,
    ADDRS.ORACLES.USDE_DAI,
    ADDRS.ORACLES.DAI_USD,  // Not used within the price, but checked that it hasn't depegged.
  );
}

runAsyncMain(main);