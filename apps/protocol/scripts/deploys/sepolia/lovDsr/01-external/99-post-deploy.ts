import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const INSTANCES = connectToContracts(owner);
  const ADDRS = getDeployedContracts();
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.SDAI_TOKEN.setInterestRate(DEFAULT_SETTINGS.EXTERNAL.SDAI_INTEREST_RATE));

  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.addMinter(
      INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );

  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.addMinter(
      INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.owner()
    )
  );
  await mine(
    INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.addMinter(
      ADDRS.CORE.MULTISIG
    )
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });