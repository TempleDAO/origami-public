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
    {
      description: "DAI/iUSDC",
      baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.DAI_USD.BASE_DECIMALS,
      // Intentionally uses the USDC token address
      // iUSDC oracle is just a proxy for the USDC price, 
      // but with 18dp instead of 6
      quoteAssetAddress: ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.IUSDC_USD.BASE_DECIMALS,
    },
    ADDRS.ORACLES.DAI_USD,
    ADDRS.ORACLES.IUSDC_USD,
    ethers.constants.AddressZero
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });