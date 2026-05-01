import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiLovToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLovToken__factory(owner);
  await deployAndMine(
    'LOV_WETH_WBTC_SHORT_A.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.LOV_WETH_WBTC_SHORT_A.TOKEN_NAME,
    DEFAULT_SETTINGS.LOV_WETH_WBTC_SHORT_A.TOKEN_SYMBOL,
    DEFAULT_SETTINGS.LOV_WETH_WBTC_SHORT_A.AUM_FEE_BPS,
    ADDRS.CORE.FEE_COLLECTOR,
    ADDRS.CORE.TOKEN_PRICES.V3,
    network.name === "localhost" ? ethers.utils.parseEther("1000000") : DEFAULT_SETTINGS.LOV_WETH_WBTC_SHORT_A.INITIAL_MAX_TOTAL_SUPPLY,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });