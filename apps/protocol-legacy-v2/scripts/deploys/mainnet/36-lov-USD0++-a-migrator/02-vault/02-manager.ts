import '@nomiclabs/hardhat-ethers';
import { OrigamiLovTokenMorphoManagerMarketAL__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);

  const factory = new OrigamiLovTokenMorphoManagerMarketAL__factory(owner);
  await deployAndMine(
    'LOV_USD0pp_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    ADDRS.LOV_USD0pp_A.TOKEN,
    ADDRS.LOV_USD0pp_A.MORPHO_BORROW_LEND,

    // Need to convert A/L 'Morpho LTV' into the 'market A/L' using this conversion
    ADDRS.ORACLES.USD0pp_MORPHO_TO_MARKET_CONVERSION,
  );
}

runAsyncMain(main);
