import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import { OrigamiLovTokenMorphoManagerMarketAL__factory } from '../../../../../typechain';
import {
  deployAndMine,
  ensureExpectedEnvvars,
} from '../../../helpers';
import { getDeployedContracts } from '../../contract-addresses';

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();

  const factory = new OrigamiLovTokenMorphoManagerMarketAL__factory(owner);
  await deployAndMine(
    'LOV_PT_SUSDE_OCT24_A.MANAGER',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    ADDRS.LOV_PT_SUSDE_OCT24_A.TOKEN,
    ADDRS.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND,
    // Need to convert A/L to 'morpho LTV' using this price
    ADDRS.ORACLES.PT_SUSDE_OCT24_DAI, 
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });