import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { IPool__factory, OrigamiAaveV3BorrowAndLend__factory } from '../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';

const OLD_BORROW_LEND_ADDRESS = '0xAeDddb1e7be3b22f328456479Eb8321E3eff212E';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const factory = new OrigamiAaveV3BorrowAndLend__factory(owner);
  const aavePool = await INSTANCES.EXTERNAL.SPARK.POOL_ADDRESS_PROVIDER.getPool();
  const oldBorrowLend = OrigamiAaveV3BorrowAndLend__factory.connect(OLD_BORROW_LEND_ADDRESS, owner);
  await deployAndMine(
    'LOV_WSTETH_A.SPARK_BORROW_LEND',
    factory,
    factory.deploy,
    ADDRS.CORE.MULTISIG,
    await oldBorrowLend.supplyToken(),
    await oldBorrowLend.borrowToken(),
    aavePool,
    await IPool__factory.connect(aavePool, owner).getUserEMode(oldBorrowLend.address)
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });