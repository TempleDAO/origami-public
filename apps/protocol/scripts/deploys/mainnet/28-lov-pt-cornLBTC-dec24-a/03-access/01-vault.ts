import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';
import { ContractAddresses } from '../../contract-addresses/types';
import { connectToContracts1, ContractInstances, getDeployedContracts1 } from '../../contract-addresses';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await mine(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.ZEROLEND_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.TOKEN),
        acceptOwner(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.ZEROLEND_BORROW_LEND),
        acceptOwner(INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER),
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
