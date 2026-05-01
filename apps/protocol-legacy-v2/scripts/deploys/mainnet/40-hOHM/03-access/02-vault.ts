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
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.hOHM.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.TELEPORTER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.TELEPORTER.setDelegate(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.hOHM.ARB_BOT.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.VAULTS.hOHM.TOKEN),
        acceptOwner(INSTANCES.VAULTS.hOHM.MANAGER),
        acceptOwner(INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER),
        acceptOwner(INSTANCES.VAULTS.hOHM.TELEPORTER),
        acceptOwner(INSTANCES.VAULTS.hOHM.ARB_BOT),
      ],
    );
  }
}

runAsyncMain(main);
