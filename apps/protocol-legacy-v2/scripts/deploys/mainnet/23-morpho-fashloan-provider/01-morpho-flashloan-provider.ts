import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiMorphoFlashLoanProvider__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts1 } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiMorphoFlashLoanProvider__factory(owner);
  await deployAndMine(
    'FLASHLOAN_PROVIDERS.MORPHO',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });