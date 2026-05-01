import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);
  await mine(INSTANCES.CORE.TOKEN_PRICES.V3.transferOwnership(ADDRS.CORE.MULTISIG));
}

runAsyncMain(main);
