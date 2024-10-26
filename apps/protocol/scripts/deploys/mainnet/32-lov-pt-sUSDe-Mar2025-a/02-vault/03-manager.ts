import '@nomiclabs/hardhat-ethers';
import { OrigamiLovTokenMorphoManagerMarketAL__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiLovTokenMorphoManagerMarketAL__factory(owner);
  await deployAndMine(
    'LOV_PT_SUSDE_MAR_2025_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.PENDLE.SUSDE_MAR_2025.PT_TOKEN,
    ADDRS.LOV_PT_SUSDE_MAR_2025_A.TOKEN,
    ADDRS.LOV_PT_SUSDE_MAR_2025_A.MORPHO_BORROW_LEND,
    // Need to convert A/L to 'morpho LTV' using this price
    ADDRS.ORACLES.PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY, 
  );
}

runAsyncMain(main);
