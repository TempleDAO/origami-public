import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import { OrigamiLovToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiLovToken__factory(owner);
  await deployAndMine(
    'LOV_PT_EBTC_DEC24_A.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.LOV_PT_EBTC_DEC24_A.TOKEN_NAME,
    DEFAULT_SETTINGS.LOV_PT_EBTC_DEC24_A.TOKEN_SYMBOL,
    DEFAULT_SETTINGS.LOV_PT_EBTC_DEC24_A.PERFORMANCE_FEE_BPS,
    ADDRS.CORE.FEE_COLLECTOR,
    ADDRS.CORE.TOKEN_PRICES.V3,
    network.name === "localhost" ? ethers.utils.parseEther("1000000") : DEFAULT_SETTINGS.LOV_PT_EBTC_DEC24_A.INITIAL_MAX_TOTAL_SUPPLY,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });