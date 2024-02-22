import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiCrossRateOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiCrossRateOracle__factory(owner);
  await deployAndMine(
    'ORACLES.DAI_IUSDC',
    factory,
    factory.deploy,
    "DAI/iUSDC",
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.ORACLES.DAI_USD,
    DEFAULT_SETTINGS.ORACLES.DAI_USD.BASE_DECIMALS,
    ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN,
    ADDRS.ORACLES.IUSDC_USD,
    DEFAULT_SETTINGS.ORACLES.IUSDC_USD.BASE_DECIMALS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });