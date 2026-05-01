import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import { mine, runAsyncMain } from '../../../helpers';
import path from 'path';
import { acceptOwner, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.SKYp.COW_SWAPPER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.SKYp.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.SKYp.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(INSTANCES.VAULTS.SKYp.COW_SWAPPER),
        acceptOwner(INSTANCES.VAULTS.SKYp.TOKEN),
        acceptOwner(INSTANCES.VAULTS.SKYp.MANAGER),
      ]
    );
    const filename = path.join(__dirname, "../access.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
