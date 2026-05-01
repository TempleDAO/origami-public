import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenFlashAndBorrowManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiLovTokenFlashAndBorrowManager__factory(owner);
  await deployAndMine(
    'LOV_PT_EBTC_DEC24_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.EBTC_DEC24.PT_TOKEN,
    ADDRS.EXTERNAL.ETHERFI.EBTC_TOKEN,
    ADDRS.EXTERNAL.PENDLE.EBTC_DEC24.PT_TOKEN,
    ADDRS.LOV_PT_EBTC_DEC24_A.TOKEN,
    ADDRS.FLASHLOAN_PROVIDERS.ZEROLEND_MAINNET_BTC,
    ADDRS.LOV_PT_EBTC_DEC24_A.ZEROLEND_BORROW_LEND,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });