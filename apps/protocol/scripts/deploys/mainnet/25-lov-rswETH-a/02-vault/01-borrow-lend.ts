import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../../typechain';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiMorphoBorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_RSWETH_A.MORPHO_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.SWELL.RSWETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
    ADDRS.EXTERNAL.MORPHO.ORACLE.RSWETH_WETH,
    ADDRS.EXTERNAL.MORPHO.IRM,
    DEFAULT_SETTINGS.LOV_RSWETH_A.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
    DEFAULT_SETTINGS.LOV_RSWETH_A.MORPHO_BORROW_LEND.SAFE_LTV,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });