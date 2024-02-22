import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedErc4626TokenPrice,
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
  // These are 'static' prices which never really change. So set the threshold to be super large.
  const stalenessThreshold = 86400 * 365 * 10;

  // $DAI and $sDAI
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.MAKER_DAO.DAI_TOKEN, 
    encodedOraclePrice(ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE, stalenessThreshold)
  ));
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, 
    encodedErc4626TokenPrice(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN)
  ));

  // $lovDSR
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.LOV_DSR.LOV_DSR_TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_DSR.LOV_DSR_TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setLendingClerk(
      ADDRS.OV_USDC.BORROW.LENDING_CLERK
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setOracle(
      ADDRS.ORACLES.DAI_IUSDC
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_DSR.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_DSR.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_DSR.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_DSR.REBALANCE_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setRedeemableReservesBufferBps(
      DEFAULT_SETTINGS.LOV_DSR.LOV_DSR_REDEEMABLE_RESERVES_BUFFER,
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setSwapper(
      ADDRS.CORE.SWAPPER_1INCH
    )
  );
  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_DSR.LOV_DSR_MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_DSR.LOV_DSR_MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_DSR.LOV_DSR_FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_DSR.LOV_DSR_TOKEN.setManager(
      ADDRS.LOV_DSR.LOV_DSR_MANAGER
    )
  );

  await mine(
    INSTANCES.OV_USDC.BORROW.LENDING_CLERK.addBorrower(
      ADDRS.LOV_DSR.LOV_DSR_MANAGER,
      ADDRS.LOV_DSR.LOV_DSR_IR_MODEL,
      DEFAULT_SETTINGS.LOV_DSR.LOV_DSR_IUSDC_BORROW_CAP
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