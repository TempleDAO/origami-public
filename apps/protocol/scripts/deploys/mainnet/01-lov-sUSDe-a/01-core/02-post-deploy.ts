import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedOraclePrice,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupPrices() {
  // USDe/USD
  const encodedUsdeToUsd = encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.USDE_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.USDE_USD_ORACLE.STALENESS_THRESHOLD
  );
  await mine(INSTANCES.CORE.TOKEN_PRICES.V1.setTokenPriceFunction(
    ADDRS.EXTERNAL.ETHENA.USDE_TOKEN, 
    encodedUsdeToUsd
  ));

  // sUSDe/USD
  const encodedSusdeToUsd = encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.SUSDE_USD_ORACLE.STALENESS_THRESHOLD
  );
  await mine(INSTANCES.CORE.TOKEN_PRICES.V1.setTokenPriceFunction(
    ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN, 
    encodedSusdeToUsd
  ));
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await setupPrices();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });