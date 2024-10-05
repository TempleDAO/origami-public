import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
  ZERO_ADDRESS,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function sdaiToSusde() {
  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.removeOrderConfig(ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN)
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.setOrderConfig(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      {
        maxSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.MIN_BUY_AMOUNT,
        limitPriceOracle: ZERO_ADDRESS,
        roundDownDivisor: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPricePremiumBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.LIMIT_PRICE_PREMIUM_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2,
        appData: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SDAI_SUSDE.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.setCowApproval(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, 
      ethers.utils.parseEther("1000"),
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.createConditionalOrder(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN)
  );
}

async function susdeToSdai() {

  // await mine(
  //   INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.removeOrderConfig(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN)
  // );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.setOrderConfig(
      ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      {
        maxSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.MIN_BUY_AMOUNT,
        limitPriceOracle: ZERO_ADDRESS,
        roundDownDivisor: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPricePremiumBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.LIMIT_PRICE_PREMIUM_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2,
        appData: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.setCowApproval(
      ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
      ethers.utils.parseEther("1000"),
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.createConditionalOrder(
      ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN
    )
  );

  // await mine(
  //   INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.updateAmountsAndPremiumBps(
  //     ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
  //     DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.MAX_SELL_AMOUNT,
  //     DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.MIN_BUY_AMOUNT,
  //     DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_2.SUSDE_SDAI.LIMIT_PRICE_PREMIUM_BPS,
  //   )
  // );
}

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await sdaiToSusde();
  // await susdeToSdai();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });