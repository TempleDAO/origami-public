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

  await mine(INSTANCES.ORACLES.USDE_DAI.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_SUSDE.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_SUSDE.MORPHO_BORROW_LEND.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_SUSDE.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Not needed in testnet, but will be in mainnet
  // await mine(INSTANCES.LOV_SUSDE.SWAPPER_1INCH.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Testnet only
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.ETHENA.SUSDE_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.setOwner(ADDRS.CORE.MULTISIG));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
