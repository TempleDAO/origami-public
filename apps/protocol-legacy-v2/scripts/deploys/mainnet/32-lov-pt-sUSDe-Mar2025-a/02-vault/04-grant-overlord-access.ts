import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(instances: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    instances.LOV_PT_SUSDE_MAR_2025_A.MANAGER, 
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );

  await setExplicitAccess(
    instances.LOV_PT_SUSDE_MAR_2025_A.TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.LOV_PT_SUSDE_MAR_2025_A.OVERLORD_WALLET, true);
}

runAsyncMain(main);
