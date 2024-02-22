import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { DummyIdleStrategy__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new DummyIdleStrategy__factory(owner);
  await deployAndMine(
    'OV_USDC.SUPPLY.AAVE_V3_IDLE_STRATEGY',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    10_000
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });