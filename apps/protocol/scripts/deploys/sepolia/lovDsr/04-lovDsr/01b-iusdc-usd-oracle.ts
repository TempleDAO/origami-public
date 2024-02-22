import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiStableChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiStableChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.IUSDC_USD',
    factory,
    factory.deploy,
    await owner.getAddress(),
    "iUSDC/USD",
    ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN,
    DEFAULT_SETTINGS.ORACLES.IUSDC_USD.BASE_DECIMALS,
    DEFAULT_SETTINGS.ORACLES.INTERNAL_USD_ADDRESS,
    DEFAULT_SETTINGS.ORACLES.IUSDC_USD.QUOTE_DECIMALS,
    DEFAULT_SETTINGS.ORACLES.IUSDC_USD.HISTORIC_PRICE,
    ADDRS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE,
    DEFAULT_SETTINGS.ORACLES.IUSDC_USD.STALENESS_THRESHOLD,
    {
      floor: DEFAULT_SETTINGS.ORACLES.IUSDC_USD.MIN_THRESHOLD,
      ceiling: DEFAULT_SETTINGS.ORACLES.IUSDC_USD.MAX_THRESHOLD
    }
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });