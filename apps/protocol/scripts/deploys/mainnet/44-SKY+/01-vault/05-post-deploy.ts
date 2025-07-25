import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedOraclePrice,
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
    vaultTokenToUsd: encodedErc4626TokenPrice(
      ADDRS.VAULTS.SKYp.TOKEN
    ),
    spkTokenToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.SPK_USD_ORACLE, 
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.SPK_USD_ORACLE.STALENESS_THRESHOLD
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.SKYp.TOKEN,
    encodedPrices.vaultTokenToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.SPARK.SPK_TOKEN,
    encodedPrices.spkTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    [
      setTokenPriceFunction(contract,
        ADDRS.VAULTS.SKYp.TOKEN,
        encodedPrices.vaultTokenToUsd
      ),
      setTokenPriceFunction(contract,
        ADDRS.EXTERNAL.SPARK.SPK_TOKEN,
        encodedPrices.spkTokenToUsd
      ),
    ],
  );

  const filename = path.join(__dirname, "../post-deploy.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

// Required for testnet run to impersonate the msig
async function setupPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V4.connect(signer));
}

async function setupPrices() { 
  updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V4);
}

async function setupCowSwapper() {
  await mine(
    INSTANCES.VAULTS.SKYp.COW_SWAPPER.setOrderConfig(
      ADDRS.EXTERNAL.SKY.USDS_TOKEN,
      {
        minSellAmount: 0,
        maxSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.SKY.SKY_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.MIN_BUY_AMOUNT, 
        roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPriceOracle: ADDRS.ORACLES.SKY_USDS,
        limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.VAULTS.SKYp.MANAGER,
        appData: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.VAULTS.SKYp.COW_SWAPPER.setCowApproval(
      ADDRS.EXTERNAL.SKY.USDS_TOKEN, 
      ethers.constants.MaxUint256
    )
  );

  await mine(
    INSTANCES.VAULTS.SKYp.COW_SWAPPER.createConditionalOrder(ADDRS.EXTERNAL.SKY.USDS_TOKEN)
  );
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  // Add the first farm
  await mine(
    INSTANCES.VAULTS.SKYp.MANAGER.addFarm(
      ADDRS.EXTERNAL.SKY.STAKING_FARMS.STAKE_SKY_EARN_USDS,
      DEFAULT_SETTINGS.VAULTS.SKYp.STAKING_FARMS.STAKE_SKY_EARN_USDS.REFERRAL_CODE,
    )
  );

  // Initial setup of config.
  await mine(
    INSTANCES.VAULTS.SKYp.TOKEN.setManager(ADDRS.VAULTS.SKYp.MANAGER, 0),
  );

  await setupCowSwapper();
  
  if (network.name === "localhost") {
    await setupPricesTestnet(owner);
  } else {
    await setupPrices();
  }
}

runAsyncMain(main);