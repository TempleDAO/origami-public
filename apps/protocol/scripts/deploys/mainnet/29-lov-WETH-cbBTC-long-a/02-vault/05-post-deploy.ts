import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedAliasFor,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { TokenPrices } from '../../../../../typechain';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    cbBtcToUsd: encodedAliasFor(ADDRS.EXTERNAL.WBTC_TOKEN),
    lovTokenToUsd: encodedRepricingTokenPrice(
      ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  // cbBTC Price
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN,
    encodedPrices.cbBtcToUsd
  ));

  // lovToken
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN,
    encodedPrices.lovTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    1,
    [
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.COINBASE.CBBTC_TOKEN,
        encodedPrices.cbBtcToUsd
      ),
      setTokenPriceFunction(contract, ADDRS.LOV_WETH_CBBTC_LONG_A.TOKEN,
        encodedPrices.lovTokenToUsd
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
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V3.connect(signer));
}

async function setupPrices() { 
  updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V3);
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.SPARK_BORROW_LEND.setPositionOwner(ADDRS.LOV_WETH_CBBTC_LONG_A.MANAGER),
  );

  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setOracles(
      ADDRS.ORACLES.WETH_CBBTC,
      ADDRS.ORACLES.WETH_CBBTC
    )
  );

  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.REBALANCE_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_WETH_CBBTC_LONG_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN.setManager(
      ADDRS.LOV_WETH_CBBTC_LONG_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_WETH_CBBTC_LONG_A.MANAGER.setAllowAll(
      true
    )
  );

  if (network.name === "localhost") {
    await setupPricesTestnet(owner);
  } else {
    await setupPrices();
  }
}

runAsyncMain(main);
