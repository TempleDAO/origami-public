import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { MockBorrowAndLend__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  const INSTANCES = connectToContracts(owner);

  const factory = new MockBorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_STETH.SPARK_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    DEFAULT_SETTINGS.LOV_STETH.MOCK_BORROW_LEND.EMODE_MAX_LTV,
    DEFAULT_SETTINGS.LOV_STETH.MOCK_BORROW_LEND.WSTETH_SUPPLY_CAP,
    DEFAULT_SETTINGS.LOV_STETH.MOCK_BORROW_LEND.WSTETH_SUPPLY_IR,
    DEFAULT_SETTINGS.LOV_STETH.MOCK_BORROW_LEND.WETH_BORROW_IR,
    ADDRS.ORACLES.WSTETH_ETH,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });