import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts1 } from '../contract-addresses';
import { OrigamiBorrowLendMigrator__factory } from '../../../../typechain';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const oldBorrowLendAddress = '0xDF3D394669Fe433713D170c6DE85f02E260c1c34';
  const factory = new OrigamiBorrowLendMigrator__factory(owner);
  await deployAndMine(
    'MIGRATOR',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    oldBorrowLendAddress,
    ADDRS.LOV_SDAI_A.MORPHO_BORROW_LEND,
    ADDRS.FLASHLOAN_PROVIDERS.MORPHO,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });