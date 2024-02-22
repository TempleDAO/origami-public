import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLendingSupplyManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLendingSupplyManager__factory(owner);
  await deployAndMine(
    'OV_USDC.SUPPLY.SUPPLY_MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
    ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN,
    ADDRS.CORE.CIRCUIT_BREAKER_PROXY,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });