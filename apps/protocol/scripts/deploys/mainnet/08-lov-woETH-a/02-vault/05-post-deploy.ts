import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TokenPrices } from '../../../../../typechain';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updatePrices(contract: TokenPrices) {
  // $lov-woETH
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_WOETH_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_WOETH_A.TOKEN)
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN,
    encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
    )
  ));

  // woETH/USD = woETH/wETH (ERC-4626) * wETH/USD (Chainlink oracle)
  const encodedEzEthToUsd = encodedErc4626TokenPrice(
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN,
  );
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN, 
    encodedEzEthToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const batch = createSafeBatch(
    1,
    [
      setTokenPriceFunction(contract, ADDRS.LOV_WOETH_A.TOKEN, 
        encodedRepricingTokenPrice(ADDRS.LOV_WOETH_A.TOKEN)
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.ORIGIN.OETH_TOKEN, 
        encodedOraclePrice(
          ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
          DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
        )
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN, 
        encodedErc4626TokenPrice(ADDRS.EXTERNAL.ORIGIN.WOETH_TOKEN)
      ),
    ],
  );

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

// Required for testnet run to impersonate the msig
async function setupPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V1.connect(signer));
}

async function setupPrices() { 
  updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V1);
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_WOETH_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_WOETH_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_WOETH_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.setOracles(
      ADDRS.ORACLES.WOETH_WETH,
      ADDRS.ORACLES.WOETH_WETH
    )
  );

  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_WOETH_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WOETH_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_WOETH_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WOETH_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_WOETH_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WOETH_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WOETH_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_WOETH_A.TOKEN.setManager(
      ADDRS.LOV_WOETH_A.MANAGER
    )
  );

  await mine(
    INSTANCES.LOV_WOETH_A.MANAGER.setAllowAll(
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