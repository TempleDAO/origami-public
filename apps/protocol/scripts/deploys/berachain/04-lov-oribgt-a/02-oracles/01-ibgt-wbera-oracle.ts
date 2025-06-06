import '@nomiclabs/hardhat-ethers';
import { IERC20Metadata__factory, OrigamiVolatileChainlinkOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiVolatileChainlinkOracle__factory(owner);
  await deployAndMine(
    'ORACLES.IBGT_WBERA',
    factory,
    factory.deploy,
    {
      description: "iBGT/WBERA",
      baseAssetAddress: ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
      baseAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, owner)).decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
      quoteAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner)).decimals(),
    },
    ADDRS.EXTERNAL.CHRONICLE.IBGT_WBERA_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHRONICLE.IBGT_WBERA_ORACLE.STALENESS_THRESHOLD,
    false, // Chronicle does not use roundId
    true  // It does use the lastUpdatedAt
  );
}

runAsyncMain(main);
