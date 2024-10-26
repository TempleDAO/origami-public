import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedMulPrice,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
  ZERO_ADDRESS,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { TokenPrices } from '../../../../../typechain';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updatePrices(contract: TokenPrices) {
  // lov-ezETH-a/USD
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_EZETH_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_EZETH_A.TOKEN)
  ));

  // ETH/USD and wETH/USD
  const encodedEthToUsd = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
  );
  await mine(contract.setTokenPriceFunction(
    ZERO_ADDRESS, 
    encodedEthToUsd,
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.WETH_TOKEN, 
    encodedEthToUsd,
  ));

  // ezETH/USD = ezETH/ETH (Redstone oracle) * ETH/USD (Chainlink oracle)
  const encodedEzEthToEth = encodedOraclePrice(
    ADDRS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.REDSTONE.EZETH_WETH_ORACLE.STALENESS_THRESHOLD
  );
  const encodedEzEthToUsd = encodedMulPrice(
    encodedEzEthToEth,
    encodedEthToUsd
  );
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.RENZO.EZETH_TOKEN, 
    encodedEzEthToUsd
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
    INSTANCES.LOV_EZETH_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_EZETH_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_EZETH_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.setOracles(
      ADDRS.ORACLES.EZETH_WETH,
      ADDRS.ORACLES.EZETH_WETH
    )
  );

  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_EZETH_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_EZETH_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_EZETH_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_EZETH_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_EZETH_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_EZETH_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_EZETH_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_EZETH_A.TOKEN.setManager(
      ADDRS.LOV_EZETH_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_EZETH_A.MANAGER.setAllowAll(
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