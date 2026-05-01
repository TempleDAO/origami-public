import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { getDeployContext } from '../../deploy-context';

async function main() {
  const {owner, ADDRS, INSTANCES} = await getDeployContext(__dirname);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_USD0pp_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  // Ensure the new manager is paused
  await mine(INSTANCES.LOV_USD0pp_A.MANAGER.setPauser(await owner.getAddress(), true));
  await mine(INSTANCES.LOV_USD0pp_A.MANAGER.setPauser(ADDRS.CORE.MULTISIG, true));
  await mine(INSTANCES.LOV_USD0pp_A.MANAGER.setPaused({
    investmentsPaused: true, 
    exitsPaused: true
  }));

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setOracles(
      ADDRS.ORACLES.USD0pp_USDC_MARKET_PRICE,
      ADDRS.ORACLES.USD0pp_USDC_MARKET_PRICE
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_USD0pp_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USD0pp_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_USD0pp_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USD0pp_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USD0pp_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setAllowAll(
      true
    )
  );
}

runAsyncMain(main);