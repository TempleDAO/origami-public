import '@nomiclabs/hardhat-ethers';
import { OrigamiInfraredVaultProxy__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiInfraredVaultProxy__factory(owner);
  await deployAndMine(
    'VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.HONEY_USDC,
  );
}

runAsyncMain(main);
