import '@nomiclabs/hardhat-ethers';
import {
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  // Grant access
  await setExplicitAccess(
    INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER, 
    ADDRS.VAULTS.BOYCO_USDC_A.OVERLORD_WALLET,
    ["deployLiquidity", "recallLiquidity"],
    true
  );
}

runAsyncMain(main);
