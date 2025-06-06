import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { TokenPrices } from '../../../../../typechain';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    lovTokenToUsd: encodedRepricingTokenPrice(
      ADDRS.LOV_MKR_DAI_LONG_A.TOKEN
    ),
    mkrTokenToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.CHAINLINK.MKR_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.MKR_USD_ORACLE.STALENESS_THRESHOLD
    ),
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.MAKER_DAO.MKR_TOKEN,
    encodedPrices.mkrTokenToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_MKR_DAI_LONG_A.TOKEN,
    encodedPrices.lovTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    [
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.MAKER_DAO.MKR_TOKEN,
        encodedPrices.mkrTokenToUsd
      ),
      setTokenPriceFunction(contract, ADDRS.LOV_MKR_DAI_LONG_A.TOKEN,
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
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  // Initial setup of config.
  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.SPARK_BORROW_LEND.setPositionOwner(ADDRS.LOV_MKR_DAI_LONG_A.MANAGER),
  );

  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setOracles(
      ADDRS.ORACLES.MKR_DAI,
      ADDRS.ORACLES.MKR_DAI
    )
  );

  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.REBALANCE_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_MKR_DAI_LONG_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.TOKEN.setManager(
      ADDRS.LOV_MKR_DAI_LONG_A.MANAGER
    )
  );

  await mine(
    INSTANCES.LOV_MKR_DAI_LONG_A.MANAGER.setAllowAll(
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