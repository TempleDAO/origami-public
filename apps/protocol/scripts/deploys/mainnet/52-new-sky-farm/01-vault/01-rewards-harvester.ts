import '@nomiclabs/hardhat-ethers';
import { OrigamiSuperSkyRewardsHarvester__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiSuperSkyRewardsHarvester__factory(owner);
  await deployAndMine(
    'VAULTS.SKYp.REWARDS_HARVESTER',
    factory,
    factory.deploy,
    ADDRS.VAULTS.SKYp.MANAGER
  );
}

runAsyncMain(main);