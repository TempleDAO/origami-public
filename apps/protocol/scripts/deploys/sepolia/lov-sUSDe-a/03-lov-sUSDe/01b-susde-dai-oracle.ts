import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiErc4626Oracle__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiErc4626Oracle__factory(owner);
  await deployAndMine(
    'ORACLES.SUSDE_DAI',
    factory,
    factory.deploy,
    {
      description: "sUSDe/DAI",
      baseAssetAddress: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      baseAssetDecimals: DEFAULT_SETTINGS.ORACLES.SUSDE_DAI.BASE_DECIMALS,
      quoteAssetAddress: ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      quoteAssetDecimals: DEFAULT_SETTINGS.ORACLES.SUSDE_DAI.QUOTE_DECIMALS,
    },
    ADDRS.ORACLES.USDE_DAI
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });