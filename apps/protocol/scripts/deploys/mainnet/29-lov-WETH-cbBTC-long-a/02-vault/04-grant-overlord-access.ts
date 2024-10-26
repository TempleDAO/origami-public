import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';

async function setAccess(instances: ContractInstances, overlordAddr: string, grantAccess: boolean) {
  await setExplicitAccess(
    instances.LOV_WETH_CBBTC_LONG_A.MANAGER,
    overlordAddr,
    ["rebalanceUp", "rebalanceDown"],
    grantAccess
  );

  await setExplicitAccess(
    instances.LOV_WETH_CBBTC_LONG_A.TOKEN,
    overlordAddr,
    ["collectPerformanceFees"],
    grantAccess
  );
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  console.log(
    ADDRS.LOV_WETH_CBBTC_LONG_A.OVERLORD_WALLET,
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.address,
    INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN.address
  )

  // Grant access
  await setAccess(INSTANCES, ADDRS.LOV_WETH_CBBTC_LONG_A.OVERLORD_WALLET, true);
}

runAsyncMain(main);
