import '@nomiclabs/hardhat-ethers';
import { OrigamiDelegated4626Vault__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiDelegated4626Vault__factory(owner);
  await deployAndMine(
    'VAULTS.ORIBGT.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.ORIBGT.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.ORIBGT.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V4,
  );
}

runAsyncMain(main);
