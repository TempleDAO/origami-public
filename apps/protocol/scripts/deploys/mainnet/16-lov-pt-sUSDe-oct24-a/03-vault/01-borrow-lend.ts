import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  deployAndMine,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { connectToContracts, ContractInstances, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { BigNumber } from 'ethers';
import { ContractAddresses } from '../../contract-addresses/types';
import { OrigamiMorphoBorrowAndLend__factory } from '../../../../../typechain';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

// Required as the market doesn't exist at time of writing
async function createMorphoMarket(
  collateralToken: string,
  loanToken: string,
  oracle: string,
  irm: string,
  lltv: BigNumber
) {
  await mine(INSTANCES.EXTERNAL.MORPHO.SINGLETON.createMarket({
    loanToken,
    collateralToken,
    oracle,
    irm,
    lltv
  }));
}

async function main() {
  ensureExpectedEnvvars();
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // The Morpho market on the PT asset doesn't exist yet
  // so we need to create locally.
  if (network.name == 'localhost') {
    await createMorphoMarket(
      ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
      ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
      ADDRS.EXTERNAL.MORPHO.ORACLE.PT_SUSDE_OCT24_DAI,
      ADDRS.EXTERNAL.MORPHO.IRM,
      DEFAULT_SETTINGS.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.LIQUIDATION_LTV
    )
  }

  const factory = new OrigamiMorphoBorrowAndLend__factory(owner);
  await deployAndMine(
    'LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND',
    factory,
    factory.deploy,
    await owner.getAddress(),
    ADDRS.EXTERNAL.PENDLE.SUSDE_OCT24.PT_TOKEN,
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN,
    ADDRS.EXTERNAL.MORPHO.SINGLETON,
    ADDRS.EXTERNAL.MORPHO.ORACLE.PT_SUSDE_OCT24_DAI,
    ADDRS.EXTERNAL.MORPHO.IRM,
    DEFAULT_SETTINGS.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.LIQUIDATION_LTV,
    DEFAULT_SETTINGS.LOV_PT_SUSDE_OCT24_A.MORPHO_BORROW_LEND.SAFE_LTV,
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });