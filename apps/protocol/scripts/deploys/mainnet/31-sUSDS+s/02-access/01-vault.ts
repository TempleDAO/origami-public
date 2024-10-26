import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import { mine, runAsyncMain } from '../../../helpers';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.SUSDSpS.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.SUSDSpS.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER),
        acceptOwner(INSTANCES.VAULTS.SUSDSpS.TOKEN),
        acceptOwner(INSTANCES.VAULTS.SUSDSpS.MANAGER),
      ],
    );
  }
}

runAsyncMain(main);
