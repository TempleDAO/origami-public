import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiLovToken__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiLovToken__factory(owner);
  await deployAndMine(
    'LOV_WETH_CBBTC_LONG_A.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.TOKEN_NAME,
    DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.TOKEN_SYMBOL,
    DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.PERFORMANCE_FEE_BPS,
    ADDRS.CORE.FEE_COLLECTOR,
    ADDRS.CORE.TOKEN_PRICES.V3,
    network.name === "localhost" ? ethers.utils.parseEther("1000000") : DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.INITIAL_MAX_TOTAL_SUPPLY,
  );
}

runAsyncMain(main);
