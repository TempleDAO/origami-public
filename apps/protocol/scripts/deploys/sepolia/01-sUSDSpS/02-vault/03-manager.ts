import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenMorphoManager__factory, OrigamiSuperSavingsUsdsManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiSuperSavingsUsdsManager__factory(owner);
  await deployAndMine(
    'VAULTS.SUSDSpS.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.VAULTS.SUSDSpS.TOKEN,
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.SWITCH_FARM_COOLDOWN_SECS,
    ADDRS.VAULTS.SUSDSpS.COW_SWAPPER,
    ADDRS.CORE.FEE_COLLECTOR,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.PERFORMANCE_FEE_FOR_CALLER_BPS,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.PERFORMANCE_FEE_FOR_ORIGAMI_BPS,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });