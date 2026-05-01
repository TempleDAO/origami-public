import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';
import { ContractAddresses } from '../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupPrices() {
  // 1 day + 15 mins
  const stalenessThreshold = 86400 + 900;

  // USDe/USD
  const encodedUsdeToUsd = encodedOraclePrice(ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE, stalenessThreshold);
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, 
    encodedUsdeToUsd
  ));

  // sUSDe/USD
  const encodedSusdeToUsd = encodedOraclePrice(ADDRS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE, stalenessThreshold);
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, 
    encodedSusdeToUsd
  ));
  
  // $lov-sUSDe-5x
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.LOV_SUSDE.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_SUSDE.TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_SUSDE.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_SUSDE.MANAGER)
  );
  await mine(
    INSTANCES.LOV_SUSDE.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.CORE.SWAPPER_1INCH
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE.MANAGER.setOracles(
      ADDRS.ORACLES.SUSDE_DAI,
      ADDRS.ORACLES.USDE_DAI
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_5X.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_5X.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_SUSDE.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_SUSDE_5X.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_SUSDE_5X.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_SUSDE_5X.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_5X.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_SUSDE_5X.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_SUSDE.TOKEN.setManager(
      ADDRS.LOV_SUSDE.MANAGER
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