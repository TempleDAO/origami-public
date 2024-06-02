import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';
import { ContractAddresses } from '../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Testnet tokens to the swapper
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.mint(
      ADDRS.LOV_USDE.SWAPPER_1INCH,
      ethers.utils.parseUnits("50000000", 18)
    )
  );
  await mine(
    INSTANCES.EXTERNAL.ETHENA.USDE_TOKEN.mint(
      ADDRS.LOV_USDE.SWAPPER_1INCH,
      ethers.utils.parseUnits("50000000", 18)
    )
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });