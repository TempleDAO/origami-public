import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.WBTC_DAI',
    factory,
    factory.deploy,
    {
      description: "wBTC/DAI",
      baseAssetAddress: ADDRS.EXTERNAL.WBTC_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.WBTC_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.CHAINLINK.BTC_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.BTC_USD_ORACLE.STALENESS_THRESHOLD,
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