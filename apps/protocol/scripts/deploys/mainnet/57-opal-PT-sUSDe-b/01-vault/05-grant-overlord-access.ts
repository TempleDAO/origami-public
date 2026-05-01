import { runAsyncMain, setExplicitAccess } from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(INSTANCES: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.VAULTS.OPAL_PT_SUSDE_B.MANAGER, 
    overlordAddr,
    ["multicall"],
    grantAccess
  );
  await setExplicitAccess(
    INSTANCES.VAULTS.OPAL_PT_SUSDE_B.TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.OPAL_PT_SUSDE_B.OVERLORD_WALLET, true);
}

runAsyncMain(main);
