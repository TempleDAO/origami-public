import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  ensureExpectedEnvvars,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts1, getDeployedContracts1 } from '../../contract-addresses';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { ContractAddresses } from '../../contract-addresses/types';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = await getDeployedContracts1(__dirname);
  INSTANCES = connectToContracts1(owner, ADDRS);

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.setOrderConfig(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN,
      {
        maxSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.MAX_SELL_AMOUNT,
        buyToken: ADDRS.EXTERNAL.ETHENA.SUSDE_TOKEN,
        minBuyAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.MIN_BUY_AMOUNT,
        limitPriceOracle: ADDRS.ORACLES.SDAI_SUSDE,
        roundDownDivisor: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.ROUND_DOWN_DIVISOR,
        partiallyFillable: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.PARTIALLY_FILLABLE,
        useCurrentBalanceForSellAmount: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.USE_CURRENT_BALANCE_FOR_SELL_AMOUNT,
        limitPricePremiumBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.LIMIT_PRICE_PREMIUM_BPS,
        verifySlippageBps: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.VERIFY_SLIPPAGE_BPS,
        expiryPeriodSecs: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.EXPIRY_PERIOD_SECS,
        recipient: ADDRS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1,
        appData: DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.APP_DATA,
      }
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.setCowApproval(
      ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN, 
      DEFAULT_SETTINGS.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.SDAI_SUSDE.MAX_SELL_AMOUNT
    )
  );

  await mine(
    INSTANCES.MAINNET_TEST.SWAPPERS.COW_SWAPPER_1.createConditionalOrder(ADDRS.EXTERNAL.MAKER_DAO.SDAI_TOKEN)
  );
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });