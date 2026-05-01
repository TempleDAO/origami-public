import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  await mine(INSTANCES.LOV_ORIBGT_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_ORIBGT_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.SWAPPERS.DIRECT_SWAPPER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.LOV_ORIBGT_A.TOKEN),
        acceptOwner(INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND),
        acceptOwner(INSTANCES.LOV_ORIBGT_A.MANAGER),
      ],
    );
  }
}

runAsyncMain(main);
