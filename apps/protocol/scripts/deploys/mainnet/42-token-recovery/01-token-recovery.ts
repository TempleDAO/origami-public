import '@nomiclabs/hardhat-ethers';
import { OrigamiTokenRecovery__factory } from '../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../helpers';
import { getDeployContext } from '../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiTokenRecovery__factory(owner);
  await deployAndMine(
    'PERIPHERY.TOKEN_RECOVERY',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
  );
}

runAsyncMain(main);
