import '@nomiclabs/hardhat-ethers';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);
  
  const factory = new OrigamiMorphoBorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_USD0pp_A.MORPHO_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
    ADDRS.EXTERNAL.MORPHO.ORACLE.USD0pp_USDC_FLOOR_PRICE,
    ADDRS.EXTERNAL.MORPHO.IRM,
    DEFAULT_SETTINGS.LOV_USD0pp_A.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
    DEFAULT_SETTINGS.LOV_USD0pp_A.MORPHO_BORROW_LEND.SAFE_LTV,
  );
}

runAsyncMain(main);
