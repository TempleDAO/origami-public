import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLendingClerk__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLendingClerk__factory(owner);
  await deployAndMine(
    'OV_USDC.BORROW.LENDING_CLERK',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
    ADDRS.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER,
    ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN,
    ADDRS.CORE.CIRCUIT_BREAKER_PROXY,
    ADDRS.OV_USDC.SUPPLY.SUPPLY_MANAGER,
    ADDRS.OV_USDC.BORROW.GLOBAL_INTEREST_RATE_MODEL,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });