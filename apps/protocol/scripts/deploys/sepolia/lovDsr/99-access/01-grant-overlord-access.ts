import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';

let INSTANCES: ContractInstances;

async function setAccess(overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.OV_USDC.SUPPLY.REWARDS_MINTER, 
    overlordAddr,
    ["checkpointDebtAndMintRewards"],
    grantAccess
  );
    
  await setExplicitAccess(
    INSTANCES.OV_USDC.BORROW.LENDING_CLERK, 
    overlordAddr,
    ["refreshBorrowersInterestRate","setIdleStrategyInterestRate"],
    grantAccess
  );
  
  await setExplicitAccess(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER, 
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );
  
  await setExplicitAccess(
    INSTANCES.LOV_DSR.LOV_DSR_TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Grant access
  await setAccess(ADDRS.CORE.OVERLORD, true);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
