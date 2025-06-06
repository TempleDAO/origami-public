import '@nomiclabs/hardhat-ethers';
import { IERC20Metadata__factory, OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS } = await getDeployContext(__dirname);

  const factory = new OrigamiErc4626Oracle__factory(owner);
  await deployAndMine(
    'ORACLES.ORIBGT_WBERA',
    factory,
    factory.deploy,
    {
      description: "oriBGT/WBERA",
      baseAssetAddress: ADDRS.VAULTS.ORIBGT.TOKEN,
      baseAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.VAULTS.ORIBGT.TOKEN, owner)).decimals(),
      quoteAssetAddress: ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
      quoteAssetDecimals: await (IERC20Metadata__factory.connect(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN, owner)).decimals(),
    },
    ADDRS.ORACLES.IBGT_WBERA,
  );
}

runAsyncMain(main);