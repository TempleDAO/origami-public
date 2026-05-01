import '@nomiclabs/hardhat-ethers';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { OrigamiEulerV2BorrowAndLend__factory } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiEulerV2BorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_ORIBGT_A.EULER_V2_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    ADDRS.EXTERNAL.EULER_V2.MARKETS.TULIPA_FOLDING_HIVE.VAULTS.ORIBGT,
    ADDRS.EXTERNAL.EULER_V2.MARKETS.TULIPA_FOLDING_HIVE.VAULTS.WBERA,
    ADDRS.EXTERNAL.EULER_V2.EVC,
  );
}

runAsyncMain(main);
