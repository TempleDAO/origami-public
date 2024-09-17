import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  ZERO_ADDRESS,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiErc4626Oracle__factory(owner);
  await deployAndMine(
    'ORACLES.WOETH_WETH',
    factory,
    factory.deploy,
    {
      description: "woETH/wETH",
      baseAssetAddress: ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.WOETH_WETH.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.WETH_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.WOETH_WETH.QUOTE_DECIMALS,
    },
    ZERO_ADDRESS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });