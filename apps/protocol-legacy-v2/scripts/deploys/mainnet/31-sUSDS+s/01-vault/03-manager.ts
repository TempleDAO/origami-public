import '@nomiclabs/hardhat-ethers';
import { OrigamiSuperSavingsUsdsManager__factory } from '../../../../../typechain';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiSuperSavingsUsdsManager__factory(owner);
  await deployAndMine(
    'VAULTS.SUSDSpS.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.SUSDSpS.TOKEN,
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.SWITCH_FARM_COOLDOWN_SECS,
    ADDRS.VAULTS.SUSDSpS.COW_SWAPPER,
    ADDRS.CORE.FEE_COLLECTOR,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.PERFORMANCE_FEE_FOR_CALLER_BPS,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.PERFORMANCE_FEE_FOR_ORIGAMI_BPS,
  );
}

runAsyncMain(main);