import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);
  const INSTANCES = connectToContracts1(owner, ADDRS);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.MKR_USDS',
    factory,
    factory.deploy,
    {
      description: "MKR/USDS",
      baseAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.MKR_TOKEN,
      baseAssetDecimals: await INSTANCES.EXTERNAL.MAKER_DAO.MKR_TOKEN.decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
      quoteAssetDecimals: await INSTANCES.EXTERNAL.SKY.USDS_TOKEN.decimals(),
    },
    ADDRS.EXTERNAL.CHAINLINK.MKR_USD_ORACLE, // Assumes USDS pegged to USD
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.MKR_USD_ORACLE.STALENESS_THRESHOLD,
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