import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiRenzoEthToEthOracle__factory } from '../../../../../typechain';
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

  const factory = new OrigamiRenzoEthToEthOracle__factory(owner);
  await deployAndMine(
    'ORACLES.EZETH_WETH',
    factory,
    factory.deploy,
    await owner.getAddress(),
    {
      description: "ezETH/wETH",
      baseAssetAddress: ADDRS.EXTERNAL.RENZO.EZETH_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.EZETH_WETH.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.WETH_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.EZETH_WETH.QUOTE_DECIMALS,
    },
    ADDRS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE.STALENESS_THRESHOLD,
    DEFAULT_SETTINGS.ORACLES.EZETH_WETH.MAX_RELATIVE_TOLERANCE_BPS,
    ADDRS.EXTERNAL.RENZO.RESTAKE_MANAGER,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });