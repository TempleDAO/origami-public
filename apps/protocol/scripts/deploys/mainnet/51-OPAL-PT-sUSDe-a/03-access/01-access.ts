import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { acceptOwnerAddr, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { IOrigamiElevatedAccess__factory } from '../../../../../typechain';

async function main() {
  const {owner, ADDRS} = await getDeployContext(__dirname);
  
  const addrs = [
    ADDRS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN.address,
    ADDRS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.MANAGER.address,
  ];
  
  for (const addr of addrs) {
    await mine(IOrigamiElevatedAccess__factory.connect(addr, owner).proposeNewOwner(ADDRS.CORE.MULTISIG));
  }

  {
    const batch = createSafeBatch(
      addrs.map(addr => acceptOwnerAddr(addr))
    );
    const filename = path.join(__dirname, "../02-access.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
