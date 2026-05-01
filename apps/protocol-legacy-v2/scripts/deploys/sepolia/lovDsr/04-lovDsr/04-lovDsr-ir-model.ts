import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { LinearWithKinkInterestRateModel__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();

  const factory = new LinearWithKinkInterestRateModel__factory(owner);
  await deployAndMine(
    'LOV_DSR.LOV_DSR_IR_MODEL',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.LOV_DSR.BORROWER_IR_AT_0_UR,
    DEFAULT_SETTINGS.LOV_DSR.BORROWER_IR_AT_100_UR,
    DEFAULT_SETTINGS.LOV_DSR.UTILIZATION_RATIO_KINK,
    DEFAULT_SETTINGS.LOV_DSR.BORROWER_IR_AT_KINK,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });