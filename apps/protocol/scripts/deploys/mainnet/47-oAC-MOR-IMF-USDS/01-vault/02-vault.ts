import '@nomiclabs/hardhat-ethers';
import { OrigamiDelegated4626Vault__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiDelegated4626Vault__factory(owner);
  await deployAndMine(
    'VAULTS.OAC_USDS_IMF_MOR.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V4,
  );
}

runAsyncMain(main);