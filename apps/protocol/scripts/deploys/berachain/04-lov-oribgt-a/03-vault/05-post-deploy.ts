import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import {
  encodedRepricingTokenPrice,
  impersonateAndFund,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { TokenPrices } from '../../../../../typechain';
import path from 'path';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    lovTokenToUsd: encodedRepricingTokenPrice(
      ADDRS.LOV_ORIBGT_A.TOKEN
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_ORIBGT_A.TOKEN,
    encodedPrices.lovTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    [
      setTokenPriceFunction(contract, ADDRS.LOV_ORIBGT_A.TOKEN,
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
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V5.connect(signer));
}

async function setupPrices() { 
  updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5);
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND.setPositionOwner(
      ADDRS.LOV_ORIBGT_A.MANAGER
    ),
  );
  await mine(
    INSTANCES.LOV_ORIBGT_A.EULER_V2_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_ORIBGT_A.MANAGER.setOracles(
      ADDRS.ORACLES.ORIBGT_WBERA,
      ADDRS.ORACLES.ORIBGT_WBERA
    )
  );

  await mine(
    INSTANCES.LOV_ORIBGT_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_ORIBGT_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_ORIBGT_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_ORIBGT_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_ORIBGT_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_ORIBGT_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_ORIBGT_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_ORIBGT_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_ORIBGT_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_ORIBGT_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_ORIBGT_A.TOKEN.setManager(
      ADDRS.LOV_ORIBGT_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_ORIBGT_A.MANAGER.setAllowAll(
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
