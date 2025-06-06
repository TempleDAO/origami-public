import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(instances: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    instances.VAULTS.hOHM.MANAGER, 
    overlordAddr,
    ["sweep"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.hOHM.OVERLORD_WALLET, true);
}

runAsyncMain(main);
