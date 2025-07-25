import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedMulPrice,
  encodedTokenPrice,
  encodedUniV3Price,
  impersonateAndFund,
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
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
      ADDRS.VAULTS.OAC_USDS_IMF_MOR.TOKEN
    ),

    imfTokenToUsd: encodedMulPrice(
      encodedUniV3Price(
        ADDRS.EXTERNAL.UNISWAP.POOLS.IMF_WETH_V3,
        true
      ),
      encodedTokenPrice(
        ADDRS.EXTERNAL.WETH_TOKEN
      )
    )
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.OAC_USDS_IMF_MOR.TOKEN,
    encodedPrices.vaultTokenToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.IMF.IMF_TOKEN,
    encodedPrices.imfTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    [
      setTokenPriceFunction(contract,
        ADDRS.VAULTS.OAC_USDS_IMF_MOR.TOKEN,
        encodedPrices.vaultTokenToUsd
      ),
      setTokenPriceFunction(contract,
        ADDRS.EXTERNAL.IMF.IMF_TOKEN,
        encodedPrices.imfTokenToUsd
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
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPER.setOrderConfig(
      ADDRS.EXTERNAL.IMF.IMF_TOKEN,
      {
        minSellAmount: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.MIN_SELL_AMOUNT,
        maxSellAmount: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.MIN_BUY_AMOUNT, 
        roundDownDivisor: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPriceOracle: ZERO_ADDRESS,
        limitPriceAdjustmentBps: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.LIMIT_PRICE_ADJUSTMENT_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.VAULTS.OAC_USDS_IMF_MOR.MANAGER,
        appData: DEFAULT_SETTINGS.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPERS.IMF_TO_USDS_LIMIT_SELL.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPER.setCowApproval(
      ADDRS.EXTERNAL.IMF.IMF_TOKEN, 
      ethers.constants.MaxUint256
    )
  );

  await mine(
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.COW_SWAPPER.createConditionalOrder(ADDRS.EXTERNAL.IMF.IMF_TOKEN)
  );
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  // Initial setup of config.
  await mine(
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.TOKEN.setManager(ADDRS.VAULTS.OAC_USDS_IMF_MOR.MANAGER, 0),
  );

  await mine(
    INSTANCES.VAULTS.OAC_USDS_IMF_MOR.MANAGER.setRewardTokens([ADDRS.EXTERNAL.IMF.IMF_TOKEN])
  );

  await setupCowSwapper();
  
  if (network.name === "localhost") {
    await setupPricesTestnet(owner);
  } else {
    await setupPrices();
  }
}

runAsyncMain(main);