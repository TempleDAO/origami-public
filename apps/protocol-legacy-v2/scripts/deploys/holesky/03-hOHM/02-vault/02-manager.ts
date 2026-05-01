import '@nomiclabs/hardhat-ethers';
import { OrigamiHOhmManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiHOhmManager__factory(owner);
  await deployAndMine(
    'VAULTS.hOHM.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.hOHM.TOKEN,
    ADDRS.EXTERNAL.OLYMPUS.MONO_COOLER,
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    DEFAULT_SETTINGS.VAULTS.hOHM.PERFORMANCE_FEE_BPS,
    ADDRS.CORE.MULTISIG,
  );
}

runAsyncMain(main);
