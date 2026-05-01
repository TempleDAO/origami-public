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
    'ORACLES.USDE_DAI',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "USDe/DAI",
      baseAssetAddress: ADDRS.EXTERNAL.ETHENA.USDE_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.USDE_DAI.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.USDE_DAI.QUOTE_DECIMALS,
    },
    DEFAULT_SETTINGS.ORACLES.USDE_DAI.HISTORIC_PRICE,
    ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE,
    DEFAULT_SETTINGS.ORACLES.USDE_DAI.STALENESS_THRESHOLD,
    {
      floor: DEFAULT_SETTINGS.ORACLES.USDE_DAI.MIN_THRESHOLD,
      ceiling: DEFAULT_SETTINGS.ORACLES.USDE_DAI.MAX_THRESHOLD
    },
    false, // Redstone does not use roundId
    true  // It does use the lastUpdatedAt
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });