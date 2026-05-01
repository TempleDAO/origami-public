import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiEtherFiEthToEthOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiEtherFiEthToEthOracle__factory(owner);
  await deployAndMine(
    'ORACLES.WEETH_WETH',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "weETH/wETH",
      baseAssetAddress: ADDRS.EXTERNAL.ETHERFI.WEETH_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.WEETH_WETH.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.WETH_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.WEETH_WETH.QUOTE_DECIMALS,
    },
    ADDRS.EXTERNAL.REDSTONE.WEETH_WETH_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WEETH_WETH_ORACLE.STALENESS_THRESHOLD,
    DEFAULT_SETTINGS.ORACLES.WEETH_WETH.MAX_RELATIVE_TOLERANCE_BPS,
    ADDRS.EXTERNAL.ETHERFI.LIQUIDITY_POOL,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });