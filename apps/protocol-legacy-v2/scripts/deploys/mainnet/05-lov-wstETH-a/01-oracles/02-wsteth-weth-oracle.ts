import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiWstEthToEthOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiWstEthToEthOracle__factory(owner);
  await deployAndMine(
    'ORACLES.WSTETH_WETH',
    factory,
    factory.deploy,
    {
      description: "wstETH/wETH",
      baseAssetAddress: ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.WSTETH_WETH.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.WETH_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.WSTETH_WETH.QUOTE_DECIMALS,
    },
    ADDRS.EXTERNAL.LIDO.STETH_TOKEN,
    ADDRS.ORACLES.STETH_WETH,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });