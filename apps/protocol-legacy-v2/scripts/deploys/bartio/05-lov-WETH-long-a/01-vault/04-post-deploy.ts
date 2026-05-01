import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  encodedScalar,
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';
import { TokenPrices } from '../../../../../typechain';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    // @todo get an actual USD oracle?
    ethToUsd: encodedScalar(ethers.utils.parseUnits("3420", 30)),
    lovTokenToUsd: encodedRepricingTokenPrice(
      ADDRS.LOV_WETH_LONG_A.TOKEN
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.WETH_TOKEN,
    encodedPrices.ethToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_WETH_LONG_A.TOKEN,
    encodedPrices.lovTokenToUsd
  ));
}

async function setupPrices() { 
  return updatePrices(INSTANCES.CORE.TOKEN_PRICES.V3);
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  await mine(
    INSTANCES.LOV_WETH_LONG_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WETH_LONG_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_WETH_LONG_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WETH_LONG_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_WETH_LONG_A.TOKEN.setManager(
      ADDRS.LOV_WETH_LONG_A.MANAGER
    )
  );

    // if (network.name === "localhost") {
    // await setupPricesTestnet(owner);
  // } else {
    await setupPrices();
  // }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });