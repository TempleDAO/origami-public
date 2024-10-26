import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import path from 'path';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';
import { getDeployContext } from '../../deploy-context';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  await mine(INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN),
        acceptOwner(INSTANCES.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND),
        acceptOwner(INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER),
      ],
    );
  }
}

runAsyncMain(main);
