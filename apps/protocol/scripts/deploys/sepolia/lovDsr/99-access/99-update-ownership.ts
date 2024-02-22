import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../contract-addresses';

let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  const ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await mine(INSTANCES.CORE.TOKEN_PRICES.transferOwnership(ADDRS.CORE.MULTISIG));

  await mine(INSTANCES.CORE.CIRCUIT_BREAKER_PROXY.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.TOKENS.OV_USDC_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.TOKENS.O_USDC_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.TOKENS.IUSDC_DEBT_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.SUPPLY.SUPPLY_MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.SUPPLY.REWARDS_MINTER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.SUPPLY.IDLE_STRATEGY_MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.SUPPLY.AAVE_V3_IDLE_STRATEGY.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.BORROW.LENDING_CLERK.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.BORROW.CIRCUIT_BREAKER_USDC_BORROW.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.BORROW.CIRCUIT_BREAKER_OUSDC_EXIT.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.OV_USDC.BORROW.GLOBAL_INTEREST_RATE_MODEL.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_DSR.LOV_DSR_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_DSR.LOV_DSR_MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.LOV_DSR.LOV_DSR_IR_MODEL.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.ORACLES.DAI_USD.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.ORACLES.IUSDC_USD.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Not needed in testnet, but will be in mainnet
  // await mine(INSTANCES.LOV_DSR.SWAPPER_1INCH.proposeNewOwner(ADDRS.CORE.MULTISIG));

  // Testnet only
  await mine(INSTANCES.EXTERNAL.MAKER_DAO.DAI_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.EXTERNAL.CIRCLE.USDC_TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
