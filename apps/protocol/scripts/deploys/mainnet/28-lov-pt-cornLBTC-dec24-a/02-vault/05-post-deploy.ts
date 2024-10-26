import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedAliasFor,
  encodedMulPrice,
  encodedOraclePrice,
  encodedOrigamiOraclePrice,
  encodedRepricingTokenPrice,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
  PriceType,
  RoundingMode,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import { TokenPrices } from '../../../../../typechain';
import path from 'path';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    lBtcToUsd: encodedAliasFor(ADDRS.EXTERNAL.WBTC_TOKEN),
    ptToUsd: encodedMulPrice(
      // PT LBTC => LBTC
      encodedOrigamiOraclePrice(
        ADDRS.ORACLES.PT_CORN_LBTC_DEC24_LBTC,
        PriceType.SPOT_PRICE, 
        RoundingMode.ROUND_DOWN
      ),
      // LBTC => USD (assume LBTC == BTC, 1:1)
      encodedAliasFor(ADDRS.EXTERNAL.WBTC_TOKEN),
    ),
    lovTokenToUsd: encodedRepricingTokenPrice(
      ADDRS.LOV_PT_CORN_LBTC_DEC24_A.TOKEN
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  // LBTC Price
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
    encodedPrices.lBtcToUsd
  ));

  // PT Price
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.PENDLE.CORN_LBTC_DEC24.PT_TOKEN,
    encodedPrices.ptToUsd
  ));

  // lovToken
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_PT_CORN_LBTC_DEC24_A.TOKEN,
    encodedPrices.lovTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    1,
    [
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.LOMBARD.LBTC_TOKEN,
        encodedPrices.lBtcToUsd
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.PENDLE.CORN_LBTC_DEC24.PT_TOKEN,
        encodedPrices.ptToUsd
      ),
      setTokenPriceFunction(contract, ADDRS.LOV_PT_CORN_LBTC_DEC24_A.TOKEN,
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
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.ZEROLEND_BORROW_LEND.setPositionOwner(
      ADDRS.LOV_PT_CORN_LBTC_DEC24_A.MANAGER
    ),
  );

  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setOracles(
      ADDRS.ORACLES.PT_CORN_LBTC_DEC24_LBTC,
      ADDRS.ORACLES.PT_CORN_LBTC_DEC24_LBTC
    )
  );

  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.REBALANCE_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_PT_CORN_LBTC_DEC24_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.TOKEN.setManager(
      ADDRS.LOV_PT_CORN_LBTC_DEC24_A.MANAGER
    )
  );
  
  await mine(
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.MANAGER.setAllowAll(
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