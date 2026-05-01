import '@nomiclabs/hardhat-ethers';
import { TokenPrices__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
    const { owner } = await getDeployContext(__dirname);

  const factory = new TokenPrices__factory(owner);
  await deployAndMine(
    'CORE.TOKEN_PRICES.V3', 
    factory, 
    factory.deploy,
    30
  );
}

runAsyncMain(main);