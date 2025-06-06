import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';
import { ContractAddresses } from '../../contract-addresses/types';

let INSTANCES: ContractInstances;

async function setAccess(overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.LOV_PT_USD0pp_MAR_2025_A.MANAGER, 
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );

  await setExplicitAccess(
    INSTANCES.LOV_PT_USD0pp_MAR_2025_A.TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  let ADDRS: ContractAddresses;
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

  // Grant access
  await setAccess(ADDRS.LOV_PT_USD0pp_MAR_2025_A.OVERLORD_WALLET, true);
}

runAsyncMain(main);