import '@nomiclabs/hardhat-ethers';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { OrigamiBorrowLendMigrator__factory } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);

  const oldBorrowLendAddress = '0x3963D8D2d7AC114573c1184F4036D9A12FbDEFe6';
  const factory = new OrigamiBorrowLendMigrator__factory(owner);
  await deployAndMine(
    'MIGRATOR',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    oldBorrowLendAddress,
    ADDRS.LOV_USD0pp_A.MORPHO_BORROW_LEND,
    ADDRS.FLASHLOAN_PROVIDERS.MORPHO,
  );
}

runAsyncMain(main);