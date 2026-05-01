import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupPrices() { 
  // $lov-sUSDe
  await mine(INSTANCES.CORE.TOKEN_PRICES.V1.setTokenPriceFunction(
    ADDRS.LOV_SUSDE_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_SUSDE_A.TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_SUSDE_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_SUSDE_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_SUSDE_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.SUSDE_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.setOracles(
      ADDRS.ORACLES.SUSDE_DAI,
      ADDRS.ORACLES.USDE_DAI
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_SUSDE_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE_A.TOKEN.setManager(
      ADDRS.LOV_SUSDE_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_SUSDE_A.MANAGER.setAllowAll(
      true
    )
  );

  await setupPrices();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });