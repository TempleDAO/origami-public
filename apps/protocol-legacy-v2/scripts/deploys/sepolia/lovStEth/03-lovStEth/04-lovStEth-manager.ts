import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenFlashAndBorrowManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLovTokenFlashAndBorrowManager__factory(owner);
  await deployAndMine(
    'LOV_STETH.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.LIDO.ST_ETH_TOKEN,
    ADDRS.LOV_STETH.TOKEN,
    ADDRS.CORE.SPARK_FLASH_LOAN_PROVIDER,
    ADDRS.LOV_STETH.SPARK_BORROW_LEND,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });