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
    'LOV_USD0pp_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    ADDRS.LOV_USD0pp_A.TOKEN,
    ADDRS.LOV_USD0pp_A.MORPHO_BORROW_LEND
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });