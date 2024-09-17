import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedMulPrice,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  encodedWstEthRatio,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { TokenPrices } from '../../../../../typechain';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updatePrices(contract: TokenPrices) {
  // lov-wstETH-a/USD
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_WSTETH_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_WSTETH_A.TOKEN)
  ));

  // stETH/USD = stETH/ETH * ETH/USD
  const encodedEthToUsd = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
  );
  const encodedStEthToEth = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.STETH_ETH_ORACLE.STALENESS_THRESHOLD
  );
  const encodedStEthToUsd = encodedMulPrice(encodedStEthToEth, encodedEthToUsd);
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.LIDO.STETH_TOKEN, 
    encodedStEthToUsd
  ));

  // wstETH/USD = wstETH/stETH * stETH/USD
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.LIDO.WSTETH_TOKEN,
    encodedMulPrice(
      encodedWstEthRatio(ADDRS.EXTERNAL.LIDO.STETH_TOKEN),
      encodedStEthToUsd
    )
  ));
}

// Required for testnet run to impersonate the msig
async function setupPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V1.connect(signer));
}

async function setupPrices() { 
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V1);
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_WSTETH_A.SPARK_BORROW_LEND.setPositionOwner(ADDRS.LOV_WSTETH_A.MANAGER),
  );
  
  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setOracles(
      ADDRS.ORACLES.WSTETH_WETH,
      ADDRS.ORACLES.STETH_WETH
    )
  );

  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_WSTETH_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WSTETH_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_WSTETH_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WSTETH_A.REBALANCE_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_WSTETH_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WSTETH_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WSTETH_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_WSTETH_A.TOKEN.setManager(
      ADDRS.LOV_WSTETH_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_WSTETH_A.MANAGER.setAllowAll(
      true
    )
  );

  if (network.name === "localhost") {
    await setupPricesTestnet(owner);
  } else {
    await setupPrices();
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });