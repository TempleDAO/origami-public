import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../helpers';
import { ContractInstances } from '../contract-addresses';
import { DEFAULT_SETTINGS } from '../default-settings';
import { ContractAddresses } from '../contract-addresses/types';
import { getDeployContext } from '../deploy-context';
import { acceptOwner, createSafeBatch, setSwapper, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function setupSusdsPlus() {
  // SKY rewards
  {
    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.setOrderConfig(
        ADDRS.EXTERNAL.SKY.SKY_TOKEN,
        {
          minSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.MIN_SELL_AMOUNT,
          maxSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.MAX_SELL_AMOUNT,
          buyToken: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
          minBuyAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.MIN_BUY_AMOUNT, 
          roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.ROUND_DOWN_DIVISOR,
          partiallyFillable: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.PARTIALLY_FILLABLE,
          useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
          limitPriceOracle: ADDRS.ORACLES.SKY_USDS,
          limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
          verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
          expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.EXPIRY_PERIOD_SECS,
          recipient: ADDRS.VAULTS.SUSDSpS.MANAGER,
          appData: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_LIMIT_SELL.APP_DATA,
        }
      )
    );

    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.setCowApproval(
        ADDRS.EXTERNAL.SKY.SKY_TOKEN, 
        ethers.constants.MaxUint256
      )
    );

    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.createConditionalOrder(ADDRS.EXTERNAL.SKY.SKY_TOKEN)
    );
  }

  // SPK rewards
  {
    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.setOrderConfig(
        ADDRS.EXTERNAL.SPARK.SPK_TOKEN,
        {
          minSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.MIN_SELL_AMOUNT,
          maxSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.MAX_SELL_AMOUNT,
          buyToken: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
          minBuyAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.MIN_BUY_AMOUNT, 
          roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.ROUND_DOWN_DIVISOR,
          partiallyFillable: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.PARTIALLY_FILLABLE,
          useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
          limitPriceOracle: ZERO_ADDRESS,
          limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
          verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
          expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.EXPIRY_PERIOD_SECS,
          recipient: ADDRS.VAULTS.SUSDSpS.MANAGER,
          appData: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SPK_TO_USDS_LIMIT_SELL.APP_DATA,
        }
      )
    );

    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.setCowApproval(
        ADDRS.EXTERNAL.SPARK.SPK_TOKEN, 
        ethers.constants.MaxUint256
      )
    );

    await mine(
      INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.createConditionalOrder(ADDRS.EXTERNAL.SPARK.SPK_TOKEN)
    );
  }
}

async function setupSkyPlus() {
  // USDS rewards
  {
    await mine(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.setOrderConfig(
        ADDRS.EXTERNAL.SKY.USDS_TOKEN,
        {
          minSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.USDS_TO_SKY_LIMIT_SELL.MIN_SELL_AMOUNT,
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
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.setCowApproval(
        ADDRS.EXTERNAL.SKY.USDS_TOKEN, 
        ethers.constants.MaxUint256
      )
    );

    await mine(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.createConditionalOrder(ADDRS.EXTERNAL.SKY.USDS_TOKEN)
    );
  }

  // SPK rewards
  {
    await mine(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.setOrderConfig(
        ADDRS.EXTERNAL.SPARK.SPK_TOKEN,
        {
          minSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.MIN_SELL_AMOUNT,
          maxSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.MAX_SELL_AMOUNT,
          buyToken: ADDRS.EXTERNAL.SKY.SKY_TOKEN,
          minBuyAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.MIN_BUY_AMOUNT, 
          roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.ROUND_DOWN_DIVISOR,
          partiallyFillable: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.PARTIALLY_FILLABLE,
          useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
          limitPriceOracle: ZERO_ADDRESS,
          limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
          verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
          expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.EXPIRY_PERIOD_SECS,
          recipient: ADDRS.VAULTS.SKYp.MANAGER,
          appData: DEFAULT_SETTINGS.VAULTS.SKYp.COW_SWAPPERS.SPK_TO_SKY_LIMIT_SELL.APP_DATA,
        }
      )
    );

    await mine(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.setCowApproval(
        ADDRS.EXTERNAL.SPARK.SPK_TOKEN, 
        ethers.constants.MaxUint256
      )
    );

    await mine(
      INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.createConditionalOrder(ADDRS.EXTERNAL.SPARK.SPK_TOKEN)
    );
  }
}

async function main() {
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  await setupSusdsPlus();
  await mine(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4.proposeNewOwner(ADDRS.CORE.MULTISIG));

  await setupSkyPlus();
  await mine(INSTANCES.VAULTS.SKYp.COW_SWAPPER_3.proposeNewOwner(ADDRS.CORE.MULTISIG));

  const batch = createSafeBatch(
    [
      setSwapper(INSTANCES.VAULTS.SUSDSpS.MANAGER, ADDRS.VAULTS.SUSDSpS.COW_SWAPPER_4),
      setSwapper(INSTANCES.VAULTS.SKYp.MANAGER, ADDRS.VAULTS.SKYp.COW_SWAPPER_3),

      acceptOwner(INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER_4),
      acceptOwner(INSTANCES.VAULTS.SKYp.COW_SWAPPER_3),
    ],
  );

  const filename = path.join(__dirname, "./transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
