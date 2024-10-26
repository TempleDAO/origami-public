import '@nomiclabs/hardhat-ethers';
import { IERC20Metadata__factory, OrigamiScaledOracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);
  
  const underlyingOracle = INSTANCES.ORACLES.PT_SUSDE_MAR_2025_DAI;
  const baseAsset = IERC20Metadata__factory.connect(await underlyingOracle.baseAsset(), owner);
  const quoteAsset = IERC20Metadata__factory.connect(await underlyingOracle.quoteAsset(), owner);

  const factory = new OrigamiScaledOracle__factory(owner);
  await deployAndMine(
    'ORACLES.PT_SUSDE_MAR_2025_DAI_WITH_DISCOUNT_TO_MATURITY',
    factory,
    factory.deploy,
    {
      description: "PT-sUSDe-Mar2025/DAI / DISCOUNT_TO_MATURITY",
      baseAssetAddress: baseAsset.address,
      baseAssetDecimals: await baseAsset.decimals(),
      quoteAssetAddress: quoteAsset.address,
      quoteAssetDecimals: await quoteAsset.decimals(),
    },
    underlyingOracle.address,
    ADDRS.ORACLES.PT_SUSDE_MAR_2025_DISCOUNT_TO_MATURITY,
    false // divide
  );
}

runAsyncMain(main);
