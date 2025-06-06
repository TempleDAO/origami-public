import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { acceptOwner, appendTransactionsToBatch, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { network } from 'hardhat';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.ORIBGT.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.ORIBGT.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.ORIBGT.SWAPPER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.CORE.TOKEN_PRICES.V4.transferOwnership(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(INSTANCES.VAULTS.ORIBGT.TOKEN),
        acceptOwner(INSTANCES.VAULTS.ORIBGT.MANAGER),
        acceptOwner(INSTANCES.VAULTS.ORIBGT.SWAPPER),
      ],
    );
    
    const filename = path.join(__dirname, "../transactions-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
