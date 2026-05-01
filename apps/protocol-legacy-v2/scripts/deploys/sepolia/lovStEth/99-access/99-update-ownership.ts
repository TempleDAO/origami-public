import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await mine(INSTANCES.CORE.TOKEN_PRICES.transferOwnership(ADDRS.CORE.MULTISIG));

  await mine(INSTANCES.ORACLES.STETH_ETH.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_STETH.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_STETH.SPARK_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_STETH.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Not needed in testnet, but will be in mainnet
  // await mine(INSTANCES.LOV_STETH.SWAPPER_1INCH.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Testnet only
  await mine(INSTANCES.EXTERNAL.WETH_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.LIDO.ST_ETH_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
