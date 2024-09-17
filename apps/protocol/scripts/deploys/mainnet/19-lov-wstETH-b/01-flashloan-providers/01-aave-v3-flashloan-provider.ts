import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiAaveV3FlashLoanProvider__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiAaveV3FlashLoanProvider__factory(owner);
  // Intentionally borrow from the mainnet aave v3, as it has more ETH
  await deployAndMine(
    'FLASHLOAN_PROVIDERS.AAVE_V3_MAINNET_HAS_FEE',
    factory,
    factory.deploy,
    ADDRS.EXTERNAL.AAVE.V3_MAINNET_POOL_ADDRESS_PROVIDER,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });