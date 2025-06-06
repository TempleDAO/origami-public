import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { acceptOwner, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { network } from 'hardhat';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.hOHM.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.TOKEN.setDelegate(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(INSTANCES.VAULTS.hOHM.TOKEN),
      ],
    );
    
    const filename = path.join(__dirname, "../transactions-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
