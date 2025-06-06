import '@nomiclabs/hardhat-ethers';
import { OrigamiDexAggregatorSwapper, OrigamiDexAggregatorSwapper__factory } from '../../../../../typechain';
import {
  deployAndMine,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiDexAggregatorSwapper__factory(owner);
  const swapper = await deployAndMine(
    'SWAPPERS.DIRECT_SWAPPER',
    factory,
    factory.deploy,
    await owner.getAddress()
  ) as OrigamiDexAggregatorSwapper;

  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2, true));
  await mine(swapper.whitelistRouter(ADDRS.EXTERNAL.OOGABOOGA.ROUTER, true));
}

runAsyncMain(main);
