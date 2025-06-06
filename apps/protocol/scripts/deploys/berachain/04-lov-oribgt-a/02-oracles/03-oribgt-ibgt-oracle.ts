import '@nomiclabs/hardhat-ethers';
import { IERC20Metadata__factory, OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiErc4626Oracle__factory(owner);
  await deployAndMine(
    'ORACLES.ORIBGT_IBGT',
    factory,
    factory.deploy,
    {
      description: "oriBGT/iBGT",
      baseAssetAddress: ADDRS.VAULTS.ORIBGT.TOKEN,
      baseAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.VAULTS.ORIBGT.TOKEN, owner)).decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
      quoteAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN, owner)).decimals(),
    },
    ZERO_ADDRESS,
  );
}

runAsyncMain(main);