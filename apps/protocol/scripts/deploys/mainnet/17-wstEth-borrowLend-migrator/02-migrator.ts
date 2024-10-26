import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { getDeployedContracts } from '../contract-addresses';
import { OrigamiBorrowLendMigrator__factory } from '../../../../typechain';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const oldBorrowLendAddress = '0xAeDddb1e7be3b22f328456479Eb8321E3eff212E';
  const factory = new OrigamiBorrowLendMigrator__factory(owner);
  await deployAndMine(
    'MIGRATOR',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    oldBorrowLendAddress,
    ADDRS.LOV_WSTETH_A.SPARK_BORROW_LEND,
    ADDRS.FLASHLOAN_PROVIDERS.SPARK,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });