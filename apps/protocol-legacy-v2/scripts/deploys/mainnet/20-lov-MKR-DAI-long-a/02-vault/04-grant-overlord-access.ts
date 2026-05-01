import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';

let INSTANCES: ContractInstances;

async function setAccess(overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER, 
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );

  await setExplicitAccess(
    INSTANCES.LOV_MKR_DAI_LONG_A.TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  // Grant access
  await setAccess(ADDRS.LOV_MKR_DAI_LONG_A.OVERLORD_WALLET, true);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
