import '@nomiclabs/hardhat-ethers';
import { OrigamiSuperSavingsUsdsVault__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiSuperSavingsUsdsVault__factory(owner);
  await deployAndMine(
    'VAULTS.SUSDSpS.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V3,
  );
}

runAsyncMain(main);