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
    INSTANCES.EXTERNAL.WETH_TOKEN.mint(
      ADDRS.CORE.SWAPPER_1INCH,
      ethers.utils.parseUnits("500000", 18)
    )
  );
  await mine(
    INSTANCES.EXTERNAL.LIDO.WST_ETH_TOKEN.mint(
      ADDRS.CORE.SWAPPER_1INCH,
      ethers.utils.parseUnits("500000", 18)
    )
  );

  // And to the flashloan provider
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.mint(
      ADDRS.CORE.SPARK_FLASH_LOAN_PROVIDER,
      ethers.utils.parseUnits("500000", 18)
    )
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });