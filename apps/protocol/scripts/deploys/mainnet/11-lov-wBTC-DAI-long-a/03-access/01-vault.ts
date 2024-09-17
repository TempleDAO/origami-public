import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();

  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await mine(INSTANCES.LOV_WBTC_DAI_LONG_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_WBTC_DAI_LONG_A.SPARK_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_WBTC_DAI_LONG_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.LOV_WBTC_DAI_LONG_A.TOKEN),
        acceptOwner(INSTANCES.LOV_WBTC_DAI_LONG_A.SPARK_BORROW_LEND),
        acceptOwner(INSTANCES.LOV_WBTC_DAI_LONG_A.MANAGER),
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
