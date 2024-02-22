import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedAliasFor,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  mine,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';
import { ContractAddresses } from '../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

// Not required in mainnet
async function forTestnet() {
  // Mint a tonne of DAI supply to sDAI
  await mine(
    INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.mint(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      ethers.utils.parseEther((100_000_000).toString()),
      {gasLimit:5000000}
    )
  );
}

async function setupPrices() {
  // $USDC
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, 
    encodedOraclePrice(ADDRS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE, DEFAULT_SETTINGS.ORACLES.IUSDC_USD.STALENESS_THRESHOLD)
  ));

  // $oUSDC
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
    encodedAliasFor(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN)
  ));

  // $ovUSDC
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN,
    encodedRepricingTokenPrice(ADDRS.OV_USDC.TOKENS.OV_USDC_TOKEN)
  ));

  // $iUSDC
  await mine(INSTANCES.CORE.TOKEN_PRICES.setTokenPriceFunction(
    ADDRS.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN,
    encodedAliasFor(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN)
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Setup the circuit breaker for daily borrows of USDC
  await mine(
    INSTANCES.CORE.CIRCUIT_BREAKER_PROXY.setIdentifierForCaller(
      ADDRS.OV_USDC.BORROW.LENDING_CLERK,
      "USDC_BORROW"
    )
  );
  await mine(
    INSTANCES.CORE.CIRCUIT_BREAKER_PROXY.setCircuitBreaker(
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("USDC_BORROW")),
      ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
      ADDRS.OV_USDC.BORROW.CIRCUIT_BREAKER_USDC_BORROW,
    )
  );
  
  // Setup the circuit breaker for exits of USDC from oUSDC
  await mine(
    INSTANCES.CORE.CIRCUIT_BREAKER_PROXY.setIdentifierForCaller(
      ADDRS.OV_USDC.SUPPLY.SUPPLY_MANAGER, 
      "OUSDC_EXIT"
    )
  );
  await mine(
    INSTANCES.CORE.CIRCUIT_BREAKER_PROXY.setCircuitBreaker(
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("OUSDC_EXIT")),
      ADDRS.OV_USDC.TOKENS.O_USDC_TOKEN,
      ADDRS.OV_USDC.BORROW.CIRCUIT_BREAKER_OUSDC_EXIT,
    )
  );

  // Hook up the lendingClerk to the supplyManager
  await mine(
    INSTANCES.OV_USDC.SUPPLY.SUPPLY_MANAGER.setLendingClerk(ADDRS.OV_USDC.BORROW.LENDING_CLERK)
  );

  // Hook up the supplyManager to oUsdc
  await mine(
    INSTANCES.OV_USDC.TOKENS.O_USDC_TOKEN.setManager(ADDRS.OV_USDC.SUPPLY.SUPPLY_MANAGER)
  );

  // Allow the lendingClerk to mint/burn iUSDC
  await mine(
    INSTANCES.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN.setMinter(ADDRS.OV_USDC.BORROW.LENDING_CLERK, true)
  );

  // Set the idle strategy interest rate
  await mine(
    INSTANCES.OV_USDC.BORROW.LENDING_CLERK.setIdleStrategyInterestRate(DEFAULT_SETTINGS.OV_USDC.IDLE_STRATEGY_IR)
  );

  // Allow the LendingManager allocate/withdraw from the idle strategy
  await setExplicitAccess(
    INSTANCES.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER, 
    ADDRS.OV_USDC.BORROW.LENDING_CLERK,
    ["allocate", "withdraw"],
    true
  );

  // Allow the idle strategy manager to allocate/withdraw to the aave strategy
  await setExplicitAccess(
    INSTANCES.OV_USDC.SUPPLY.AAVE_V3_IDLE_STRATEGY,
    ADDRS.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER, 
    ["allocate", "withdraw"],
    true
  );

  // Allow the RewardsMinter to mint new oUSDC and add as pending reserves into ovUSDC
  await mine(
    INSTANCES.OV_USDC.TOKENS.O_USDC_TOKEN.addMinter(ADDRS.OV_USDC.SUPPLY.REWARDS_MINTER)
  );
  await setExplicitAccess(
    INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN,
    ADDRS.OV_USDC.SUPPLY.REWARDS_MINTER, 
    ["addPendingReserves"],
    true
  );

  // Set the idle strategy config
  await mine(
    INSTANCES.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER.setIdleStrategy(ADDRS.OV_USDC.SUPPLY.AAVE_V3_IDLE_STRATEGY)
  );
  await mine(
    INSTANCES.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER.setThresholds(
      DEFAULT_SETTINGS.OV_USDC.AAVE_STRATEGY_DEPOSIT_THRESHOLD,
      DEFAULT_SETTINGS.OV_USDC.AAVE_STRATEGY_WITHDRAWAL_THRESHOLD,
    )
  );
  await mine(
    INSTANCES.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER.setDepositsEnabled(true)
  );

  await forTestnet();
  await setupPrices();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });