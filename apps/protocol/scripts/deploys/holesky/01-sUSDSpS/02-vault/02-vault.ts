import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiSuperSavingsUsdsVault__factory } from '../../../../../typechain';
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

  const factory = new OrigamiSuperSavingsUsdsVault__factory(owner);
  await deployAndMine(
    'VAULTS.SUSDSpS.TOKEN',
    factory,
    factory.deploy,
    await owner.getAddress(),
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.TOKEN_NAME,
    DEFAULT_SETTINGS.VAULTS.SUSDSpS.TOKEN_SYMBOL,
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    ADDRS.CORE.TOKEN_PRICES.V3,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });