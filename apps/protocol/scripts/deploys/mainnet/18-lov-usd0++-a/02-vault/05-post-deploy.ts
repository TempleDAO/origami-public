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
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TokenPrices } from '../../../../../typechain';
import { createSafeBatch, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updatePrices(contract: TokenPrices) {
  // lov-USD0++/USD
  await mine(contract.setTokenPriceFunction(
    ADDRS.LOV_USD0pp_A.TOKEN,
    encodedRepricingTokenPrice(ADDRS.LOV_USD0pp_A.TOKEN)
  ));

  // USDC/USD [chainlink]
  const encodedUsdc = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE.STALENESS_THRESHOLD
  );
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    encodedUsdc
  ));

  // USD0/USD
  // == USD0/USDC * USDC/USD [chainlink]
  const encodedUsd0 = encodedMulPrice(
    encodedOrigamiOraclePrice(ADDRS.ORACLES.USD0_USDC, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN),
    encodedAliasFor(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN)
  );
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.USUAL.USD0_TOKEN,
    encodedUsd0
  ));

  // USD0++/USD
  // == USD0++/USD0 * USD0/USD
  const encodedUsd0pp = encodedMulPrice(
    encodedOrigamiOraclePrice(ADDRS.ORACLES.USD0pp_USD0, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN),
    encodedAliasFor(ADDRS.EXTERNAL.USUAL.USD0_TOKEN)
  );
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN,
    encodedUsd0pp
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const batch = createSafeBatch(
    1,
    [
      setTokenPriceFunction(contract, ADDRS.LOV_USD0pp_A.TOKEN, 
        encodedRepricingTokenPrice(ADDRS.LOV_USD0pp_A.TOKEN)
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN, 
        encodedOraclePrice(
          ADDRS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE, 
          DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.USDC_USD_ORACLE.STALENESS_THRESHOLD
        )
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.USUAL.USD0_TOKEN, 
        encodedMulPrice(
          encodedOrigamiOraclePrice(ADDRS.ORACLES.USD0_USDC, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN),
          encodedAliasFor(ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN)
        )
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.USUAL.USD0pp_TOKEN, 
        encodedMulPrice(
          encodedOrigamiOraclePrice(ADDRS.ORACLES.USD0pp_USD0, PriceType.SPOT_PRICE, RoundingMode.ROUND_DOWN),
          encodedAliasFor(ADDRS.EXTERNAL.USUAL.USD0_TOKEN)
        )
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
    INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.setPositionOwner(ADDRS.LOV_USD0pp_A.MANAGER),
  );
  await mine(
    INSTANCES.LOV_USD0pp_A.MORPHO_BORROW_LEND.setSwapper(
      ADDRS.SWAPPERS.DIRECT_SWAPPER
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setOracles(
      ADDRS.ORACLES.USD0pp_USDC,
      ADDRS.ORACLES.USD0pp_USDC
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setUserALRange(
      DEFAULT_SETTINGS.LOV_USD0pp_A.USER_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USD0pp_A.USER_AL_CEILING
    )
  );
  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setRebalanceALRange(
      DEFAULT_SETTINGS.LOV_USD0pp_A.REBALANCE_AL_FLOOR,
      DEFAULT_SETTINGS.LOV_USD0pp_A.REBALANCE_AL_CEILING
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setFeeConfig(
      DEFAULT_SETTINGS.LOV_USD0pp_A.MIN_DEPOSIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USD0pp_A.MIN_EXIT_FEE_BPS,
      DEFAULT_SETTINGS.LOV_USD0pp_A.FEE_LEVERAGE_FACTOR
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.TOKEN.setManager(
      ADDRS.LOV_USD0pp_A.MANAGER
    )
  );

  await mine(
    INSTANCES.LOV_USD0pp_A.MANAGER.setAllowAll(
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