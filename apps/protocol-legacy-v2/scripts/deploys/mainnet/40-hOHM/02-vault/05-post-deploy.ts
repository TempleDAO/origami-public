import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedMulPrice,
  encodedOraclePrice,
  encodedScalar,
  encodedTokenizedBalanceSheetTokenPrice,
  encodedTokenPrice,
  encodedUniV3Price,
  mine,
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => {
  // A fixed conversion rate - to 30dp
  const ohm_per_gohm = encodedScalar(
    DEFAULT_SETTINGS.EXTERNAL.OLYMPUS.OHM_PER_GOHM.mul(ethers.utils.parseUnits("1", 30-18))
  );

  // https://www.defined.fi/eth/0x88051b0eea095007d3bef21ab287be961f3d8598?quoteToken=token0&quoteCurrency=TOKEN
  const ohm_per_weth = encodedUniV3Price(ADDRS.EXTERNAL.UNISWAP.POOLS.OHM_WETH_V3, true);
  const usd_per_weth = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE, 
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.ETH_USD_ORACLE.STALENESS_THRESHOLD
  );
  const usd_per_ohm = encodedMulPrice(usd_per_weth, ohm_per_weth);

  // Can just use the DAI/USD rate
  const usd_per_usds = encodedOraclePrice(
    ADDRS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE,
    DEFAULT_SETTINGS.EXTERNAL.CHAINLINK.DAI_USD_ORACLE.STALENESS_THRESHOLD,
  );

  return {
    usdsToUsd: usd_per_usds,
    ethToUsd: usd_per_weth,
    ohmToUsd: usd_per_ohm,
    gohmToUsd: encodedMulPrice(encodedTokenPrice(ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN), ohm_per_gohm),   
    vaultToUsd: encodedTokenizedBalanceSheetTokenPrice(ADDRS.VAULTS.hOHM.TOKEN),
  }
};

async function setupPrices() {
  const contract = INSTANCES.CORE.TOKEN_PRICES.V4;
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN,
    encodedPrices.ohmToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.OLYMPUS.GOHM_TOKEN,
    encodedPrices.gohmToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.hOHM.TOKEN,
    encodedPrices.vaultToUsd
  ));
}

async function main() {
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

  await mine(
    INSTANCES.VAULTS.hOHM.TOKEN.setManager(
      ADDRS.VAULTS.hOHM.MANAGER
    )
  );
  await mine(
    INSTANCES.VAULTS.hOHM.MANAGER.setExitFees(
      DEFAULT_SETTINGS.VAULTS.hOHM.EXIT_FEE_BPS
    )
  );
  await mine(
    INSTANCES.VAULTS.hOHM.MANAGER.setSweepParams(
      DEFAULT_SETTINGS.VAULTS.hOHM.SWEEP_COOLDOWN_SECS,
      DEFAULT_SETTINGS.VAULTS.hOHM.SWEEP_MAX_SELL_AMOUNT,
    )
  );
  await mine(
    INSTANCES.VAULTS.hOHM.MANAGER.setSweepSwapper(
      ADDRS.VAULTS.hOHM.SWEEP_SWAPPER,
    )
  );
  await setExplicitAccess(
    INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER, 
    ADDRS.VAULTS.hOHM.MANAGER,
    ["execute"],
    true
  );

  await mine(INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.ONE_INCH.ROUTER_V6, true));
  await mine(INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.KYBERSWAP.ROUTER_V2, true));
  await mine(INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER.whitelistRouter(ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, true));

  await setupPrices();
}

runAsyncMain(main);
