import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

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

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
