import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenFlashAndBorrowManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLovTokenFlashAndBorrowManager__factory(owner);
  await deployAndMine(
    'LOV_WETH_SDAI_SHORT_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
    ADDRS.LOV_WETH_SDAI_SHORT_A.TOKEN,
    ADDRS.FLASHLOAN_PROVIDERS.SPARK,
    ADDRS.LOV_WETH_SDAI_SHORT_A.SPARK_BORROW_LEND
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });