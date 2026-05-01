import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiStableChainlinkOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiStableChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.STETH_WETH',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "stETH/wETH",
      baseAssetAddress: ADDRS.EXTERNAL.LIDO.STETH_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.STETH_WETH.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.WETH_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.STETH_WETH.QUOTE_DECIMALS,
    },
    DEFAULT_SETTINGS.ORACLES.STETH_WETH.HISTORIC_PRICE,
    ADDRS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE.STALENESS_THRESHOLD,
    {
      floor: DEFAULT_SETTINGS.ORACLES.STETH_WETH.MIN_THRESHOLD,
      ceiling: DEFAULT_SETTINGS.ORACLES.STETH_WETH.MAX_THRESHOLD
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