import { runAsyncMain, setExplicitAccess } from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(INSTANCES: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.MANAGER, 
    overlordAddr,
    ["multicall"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.OVERLORD_WALLET, true);
}

runAsyncMain(main);
