import '@nomiclabs/hardhat-ethers';
import { OrigamiErc4626WithRewardsManager__factory, OrigamiSuperSkyManager__factory } from '../../../../../typechain';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { deployAndMine, runAsyncMain, ZERO_ADDRESS } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiErc4626WithRewardsManager__factory(owner);
  await deployAndMine(
    'VAULTS.OAC_USDS_IMF_MOR.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.OAC_USDS_IMF_MOR.TOKEN,
    ADDRS.EXTERNAL.MORPHO.EARN_VAULTS.IMF_USDS,
    ADDRS.CORE.FEE_COLLECTOR,
    ADDRS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPER,
    DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.PERFORMANCE_FEE_FOR_ORIGAMI_BPS,
    DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.REWARDS_VESTING_DURATION_SECS,
    ADDRS.EXTERNAL.MERKL.REWARDS_DISTRIBUTOR,
    ZERO_ADDRESS, // No Morpho rewards distribution on this
  );
}

runAsyncMain(main);