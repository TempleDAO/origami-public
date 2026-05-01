import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ZERO_ADDRESS,
  encodedMulPrice,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  encodedWstEthRatio,
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

  // ETH/USD & wETH/USD
  const encodedEthToUsd = encodedOraclePrice(ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, stalenessThreshold);
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ZERO_ADDRESS, 
    encodedEthToUsd
  ));
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.WETH_TOKEN, 
    encodedEthToUsd
  ));

  // stETH/USD = stETH/ETH * ETH/USD
  const encodedStEthToEth = encodedOraclePrice(ADDRS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE, stalenessThreshold);
  const encodedStEthToUsd = encodedMulPrice(encodedStEthToEth, encodedEthToUsd);
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.LIDO.ST_ETH_TOKEN, 
    encodedStEthToUsd
  ));

  // wstETH/USD = wstETH/stETH * stETH/USD
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.LIDO.WST_ETH_TOKEN,
    encodedMulPrice(
      encodedWstEthRatio(ADDRS.EXTERNAL.LIDO.ST_ETH_TOKEN),
      encodedStEthToUsd
    )
  ));
  
  // $lovStEth
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.LOV_STETH.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_STETH.TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_STETH.SPARK_BORROW_LEND.setPositionOwner(ADDRS.LOV_STETH.MANAGER)
  );

  await mine(
    INSTANCES.LOV_STETH.MANAGER.setOracles(
      ADDRS.ORACLES.WSTETH_ETH,
      ADDRS.ORACLES.STETH_ETH
    )
  );

  await mine(
    INSTANCES.LOV_STETH.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_STETH.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_STETH.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_STETH.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_STETH.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_STETH.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_STETH.MANAGER.setSwapper(
      ADDRS.CORE.SWAPPER_1INCH
    )
  );
  await mine(
    INSTANCES.LOV_STETH.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_STETH.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_STETH.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_STETH.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_STETH.TOKEN.setManager(
      ADDRS.LOV_STETH.MANAGER
    )
  );

  await setupPrices();

  // Testnet only -- supply wETH into the mock aave
  await mine(
    INSTANCES.EXTERNAL.WETH_TOKEN.mint(
      await INSTANCES.LOV_STETH.SPARK_BORROW_LEND.escrow(),
      ethers.utils.parseUnits("500000", 18)
    )
  );

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });