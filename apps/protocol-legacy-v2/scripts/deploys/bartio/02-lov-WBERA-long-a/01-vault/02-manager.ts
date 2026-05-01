import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiTestnetLovTokenManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiTestnetLovTokenManager__factory(owner);
  await deployAndMine(
    'LOV_WBERA_LONG_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    ADDRS.LOV_WBERA_LONG_A.TOKEN,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });