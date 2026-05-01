import '@nomiclabs/hardhat-ethers';
import { OrigamiLanternOffering__factory } from '../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';

async function main() {
  const { owner } = await getDeployContext(__dirname);

  const factory = new OrigamiLanternOffering__factory(owner);
  await deployAndMine(
    'PERIPHERY.LANTERN_OFFERING', 
    factory, 
    factory.deploy,
    await owner.getAddress()
  );
}

runAsyncMain(main);
