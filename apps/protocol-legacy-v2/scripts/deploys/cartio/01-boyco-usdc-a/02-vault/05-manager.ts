import '@nomiclabs/hardhat-ethers';
import { OrigamiBoycoUsdcManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiBoycoUsdcManager__factory(owner);
  await deployAndMine(
    'VAULTS.BOYCO_USDC_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.VAULTS.BOYCO_USDC_A.BEX_POOL_HELPERS.HONEY_USDC,
    ADDRS.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC,
  );
}

runAsyncMain(main);
