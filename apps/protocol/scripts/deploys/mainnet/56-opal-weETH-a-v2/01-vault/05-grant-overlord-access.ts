import '@nomiclabs/hardhat-ethers';
import { runAsyncMain, setExplicitAccess } from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(INSTANCES: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.VAULTS.OPAL_WEETH_A.MANAGER, 
    overlordAddr,
    ["multicall"],
    grantAccess
  );
  await setExplicitAccess(
    INSTANCES.VAULTS.OPAL_WEETH_A.TOKEN, 
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.OPAL_WEETH_A.OVERLORD_WALLET, true);
}

runAsyncMain(main);
