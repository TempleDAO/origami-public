import '@nomiclabs/hardhat-ethers';
import { OrigamiSuperSkyManager__factory } from '../../../../../typechain';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiSuperSkyManager__factory(owner);
  await deployAndMine(
    'VAULTS.SKYp.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.SKYp.TOKEN,
    ADDRS.EXTERNAL.SKY.LOCKSTAKE_ENGINE,
    DEFAULT_SETTINGS.VAULTS.SKYp.SWITCH_FARM_COOLDOWN_SECS,
    ADDRS.VAULTS.SKYp.COW_SWAPPER,
    ADDRS.CORE.FEE_COLLECTOR,
    DEFAULT_SETTINGS.VAULTS.SKYp.PERFORMANCE_FEE_FOR_CALLER_BPS,
    DEFAULT_SETTINGS.VAULTS.SKYp.PERFORMANCE_FEE_FOR_ORIGAMI_BPS,
  );
}

runAsyncMain(main);