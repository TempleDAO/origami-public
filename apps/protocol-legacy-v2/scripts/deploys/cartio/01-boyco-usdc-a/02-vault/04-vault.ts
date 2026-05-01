import '@nomiclabs/hardhat-ethers';
import { OrigamiDelegated4626Vault__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiDelegated4626Vault__factory(owner);
  await deployAndMine(
    'VAULTS.BOYCO_USDC_A.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.BOYCO_USDC_A.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.BOYCO_USDC_A.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V3,
  );
}

runAsyncMain(main);
