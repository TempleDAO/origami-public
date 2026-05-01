import '@nomiclabs/hardhat-ethers';
import { runAsyncMain, setExplicitAccess } from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(INSTANCES: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    INSTANCES.VAULTS.SUSDSpS.MANAGER, 
    overlordAddr,
    ["switchFarms"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setAccess(INSTANCES, ADDRS.VAULTS.SUSDSpS.OVERLORD_WALLET, true);
}

runAsyncMain(main);
