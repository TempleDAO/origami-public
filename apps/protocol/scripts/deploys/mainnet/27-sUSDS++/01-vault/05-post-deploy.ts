import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  encodedErc4626TokenPrice,
  encodedOraclePrice,
  encodedScalar,
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
  ZERO_ADDRESS,
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
    // @todo Should be updated when there's a Chainlink oracle
    usdsToUsd: encodedScalar(ethers.utils.parseUnits("1", 30)),

    // usdsToUsd: encodedOraclePrice(
    //   ADDRS.EXTERNAL.CHRONICLE.USDS_USD_ORACLE,
    //   DEFAULT_SETTINGS.EXTERNAL.CHRONICLE.USDS_USD_ORACLE.STALENESS_THRESHOLD,
    // ),

    sUsdsToUsd: encodedErc4626TokenPrice(ADDRS.EXTERNAL.SKY.SUSDS_TOKEN),
    
    // skyToUsd: encodedOraclePrice(
    //   ADDRS.EXTERNAL.CHRONICLE.SKY_USD_ORACLE,
    //   DEFAULT_SETTINGS.EXTERNAL.CHRONICLE.SKY_USD_ORACLE.STALENESS_THRESHOLD,
    // ),

    vaultTokenToUsd: encodedErc4626TokenPrice(
      ADDRS.VAULTS.SUSDSpS.TOKEN
    ),
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    encodedPrices.usdsToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
    encodedPrices.sUsdsToUsd
  ));
  // await mine(contract.setTokenPriceFunction(
  //   ADDRS.EXTERNAL.SKY.SKY_TOKEN,
  //   encodedPrices.skyToUsd
  // ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.SUSDSpS.TOKEN,
    encodedPrices.vaultTokenToUsd
  ));
}

async function updatePricesSafeBatch(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  const batch = createSafeBatch(
    1,
    [
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.SKY.USDS_TOKEN,
        encodedPrices.usdsToUsd
      ),
      setTokenPriceFunction(contract, ADDRS.EXTERNAL.SKY.SUSDS_TOKEN,
        encodedPrices.sUsdsToUsd
      ),
      // setTokenPriceFunction(contract, ADDRS.EXTERNAL.SKY.SKY_TOKEN,
      //   encodedPrices.skyToUsd
      // ),
      setTokenPriceFunction(contract, ADDRS.VAULTS.SUSDSpS.TOKEN,
        encodedPrices.vaultTokenToUsd
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

async function setupCowSwapper() {
  await mine(
    INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER.setOrderConfig(
      ADDRS.EXTERNAL.SKY.SKY_TOKEN,
      {
        maxSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.SKY.USDS_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.MIN_BUY_AMOUNT,
        limitPriceOracle: ZERO_ADDRESS,
        roundDownDivisor: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPricePremiumBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.LIMIT_PRICE_PREMIUM_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.VAULTS.SUSDSpS.MANAGER,
        appData: DEFAULT_SETTINGS.VAULTS.SUSDSpS.COW_SWAPPERS.SKY_TO_USDS_EXACT_SELL_AMOUNT.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER.setCowApproval(
      ADDRS.EXTERNAL.SKY.SKY_TOKEN, 
      ethers.constants.MaxUint256
    )
  );

  await mine(
    INSTANCES.VAULTS.SUSDSpS.COW_SWAPPER.createConditionalOrder(ADDRS.EXTERNAL.SKY.SKY_TOKEN)
  );
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  // Add the first SKY farm
  await mine(
    INSTANCES.VAULTS.SUSDSpS.MANAGER.addFarm(
      ADDRS.EXTERNAL.SKY.STAKING_FARMS.USDS_SKY,
      DEFAULT_SETTINGS.VAULTS.SUSDSpS.STAKING_FARMS.USDS_SKY.REFERRAL_CODE,
    )
  );

  // Initial setup of config.
  await mine(
    INSTANCES.VAULTS.SUSDSpS.TOKEN.setManager(ADDRS.VAULTS.SUSDSpS.MANAGER),
  );

  await setupCowSwapper();
  
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