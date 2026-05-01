import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiDebtToken__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new OrigamiDebtToken__factory(owner);
  await deployAndMine(
    'OV_USDC.TOKENS.IUSDC_DEBT_TOKEN',
    factory,
    factory.deploy,
    "Origami iUSDC",
    "iUSDC",
    await owner.getAddress(),
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });