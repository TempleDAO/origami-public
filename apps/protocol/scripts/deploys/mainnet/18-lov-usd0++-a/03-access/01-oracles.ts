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

  await mine(INSTANCES.ORACLES.USD0pp_USD0.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.ORACLES.USD0_USDC.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.ORACLES.USD0pp_USD0),
        acceptOwner(INSTANCES.ORACLES.USD0_USDC),
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
