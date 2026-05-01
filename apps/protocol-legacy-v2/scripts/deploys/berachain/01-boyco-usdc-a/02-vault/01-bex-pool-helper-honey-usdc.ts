import '@nomiclabs/hardhat-ethers';
import { OrigamiBalancerComposableStablePoolHelper__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiBalancerComposableStablePoolHelper__factory(owner);
  await deployAndMine(
    'VAULTS.BOYCO_USDC_A.BEX_POOL_HELPERS.HONEY_USDC',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    ADDRS.EXTERNAL.BEX.BALANCER_VAULT,
    ADDRS.EXTERNAL.BEX.BALANCER_QUERIES,
    await INSTANCES.EXTERNAL.BEX.LP_TOKENS.HONEY_USDC.getPoolId(),
  );
}

runAsyncMain(main);
