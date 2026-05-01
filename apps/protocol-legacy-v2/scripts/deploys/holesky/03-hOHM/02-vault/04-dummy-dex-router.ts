import '@nomiclabs/hardhat-ethers';
import { DummyDexRouter__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new DummyDexRouter__factory(owner);
  await deployAndMine(
    'VAULTS.hOHM.DUMMY_DEX_ROUTER',
    factory,
    factory.deploy,
  );
}

runAsyncMain(main);
