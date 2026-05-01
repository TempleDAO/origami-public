import '@nomiclabs/hardhat-ethers';
import { OrigamiTokenTeleporter__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiTokenTeleporter__factory(owner);
  await deployAndMine(
    'VAULTS.hOHM.TELEPORTER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.hOHM.TOKEN,
    ADDRS.EXTERNAL.LAYER_ZERO.ENDPOINT,
    await owner.getAddress(),
  );
}

runAsyncMain(main);