import '@nomiclabs/hardhat-ethers';
import { OrigamiHOhmVault__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiHOhmVault__factory(owner);
  await deployAndMine(
    'VAULTS.hOHM.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.hOHM.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.hOHM.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V4,
  );
}

runAsyncMain(main);
