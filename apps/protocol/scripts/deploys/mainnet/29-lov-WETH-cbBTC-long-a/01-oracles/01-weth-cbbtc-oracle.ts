import '@nomiclabs/hardhat-ethers';
import { OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import { deployAndMine, runAsyncMain } from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);

  const baseAsset = INSTANCES.EXTERNAL.WETH_TOKEN;
  const quoteAsset = INSTANCES.EXTERNAL.COINBASE.CBBTC_TOKEN;

  await deployAndMine(
    'ORACLES.WETH_CBBTC',
    factory,
    factory.deploy,
    {
      description: "WETH/cbBTC",
      baseAssetAddress: baseAsset.address,
      baseAssetDecimals: await baseAsset.decimals(),
      quoteAssetAddress: quoteAsset.address,
      quoteAssetDecimals: await quoteAsset.decimals(),
    },
    ADDRS.EXTERNAL.CHAINLINK.ETH_BTC_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_BTC_ORACLE.STALENESS_THRESHOLD,
    true, // Chainlink does use roundId
    true  // It does use the lastUpdatedAt
  );
}

runAsyncMain(main);
