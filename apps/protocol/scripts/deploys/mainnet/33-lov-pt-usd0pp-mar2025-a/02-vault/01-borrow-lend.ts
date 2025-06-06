import '@nomiclabs/hardhat-ethers';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiMorphoBorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.USD0pp_MAR_2025.PT_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
    ADDRS.EXTERNAL.MORPHO.ORACLE.PT_USD0pp_MAR_2025_USDC_PEGGED,
    ADDRS.EXTERNAL.MORPHO.IRM,
    DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
    DEFAULT_SETTINGS.LOV_PT_USD0pp_MAR_2025_A.MORPHO_BORROW_LEND.SAFE_LTV,
  );
}

runAsyncMain(main);