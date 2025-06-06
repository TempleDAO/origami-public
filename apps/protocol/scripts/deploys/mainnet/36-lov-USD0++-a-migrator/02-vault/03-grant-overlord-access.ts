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
    INSTANCES.LOV_USD0pp_A.MANAGER, 
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );
}

async function main() {
  let ADDRS: ContractAddresses;
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

  // Grant access
  await setAccess(ADDRS.LOV_USD0pp_A.OVERLORD_WALLET, true);
}

runAsyncMain(main);