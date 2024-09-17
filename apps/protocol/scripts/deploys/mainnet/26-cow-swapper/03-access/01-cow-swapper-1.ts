import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await mine(INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      1,
      [
        acceptOwner(INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1),
      ],
    );
  
    const filename = path.join(__dirname, "../transactions-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
