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
    'ORACLES.DAI_USD',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "DAI/USD",
      baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.DAI_USD.BASE_DECIMALS,
      quoteAssetAddress: DEFAULT_SETTINGS.ORACLES.INTERNAL_USD_ADDRESS,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.DAI_USD.QUOTE_DECIMALS,
    },
    DEFAULT_SETTINGS.ORACLES.DAI_USD.HISTORIC_PRICE,
    ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE,
    DEFAULT_SETTINGS.ORACLES.DAI_USD.STALENESS_THRESHOLD,
    {
      floor: DEFAULT_SETTINGS.ORACLES.DAI_USD.MIN_THRESHOLD, 
      ceiling: DEFAULT_SETTINGS.ORACLES.DAI_USD.MAX_THRESHOLD
    },
    true, // Chainlink does use roundId
    true  // It does use the lastUpdatedAt
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });