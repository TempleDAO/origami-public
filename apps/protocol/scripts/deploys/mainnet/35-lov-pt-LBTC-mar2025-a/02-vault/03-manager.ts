import '@nomiclabs/hardhat-ethers';
import { OrigamiLovTokenMorphoManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiLovTokenMorphoManager__factory(owner);
  await deployAndMine(
    'LOV_PT_LBTC_MAR_2025_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN,
    ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
    ADDRS.EXTERNAL.PENDLE.LBTC_MAR_2025.PT_TOKEN,
    ADDRS.LOV_PT_LBTC_MAR_2025_A.TOKEN,
    ADDRS.LOV_PT_LBTC_MAR_2025_A.MORPHO_BORROW_LEND
  );
}

runAsyncMain(main);