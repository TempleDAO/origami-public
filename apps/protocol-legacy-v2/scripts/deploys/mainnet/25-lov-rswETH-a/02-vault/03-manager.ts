import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenMorphoManager__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts1 } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = await getDeployedContracts1(__dirname);

  const factory = new OrigamiLovTokenMorphoManager__factory(owner);
  await deployAndMine(
    'LOV_RSWETH_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.SWELL.RSWETH_TOKEN,
    ADDRS.EXTERNAL.WETH_TOKEN,
    ADDRS.EXTERNAL.SWELL.RSWETH_TOKEN,
    ADDRS.LOV_RSWETH_A.TOKEN,
    ADDRS.LOV_RSWETH_A.MORPHO_BORROW_LEND
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });