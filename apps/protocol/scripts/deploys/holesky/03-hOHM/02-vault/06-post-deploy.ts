import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedMulPrice,
  encodedScalar,
  encodedTokenizedBalanceSheetTokenPrice,
  encodedTokenPrice,
  mine,
  runAsyncMain,
  setExplicitAccess,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { TokenPrices } from '../../../../../typechain';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => {
  // A fixed conversion rate
  const ohm_per_gohm = encodedScalar(ethers.utils.parseUnits("269.24", 30));

  // @todo Mainnet will likely need to be the Univ3 pool
  // eg https://www.defined.fi/eth/0x88051b0eea095007d3bef21ab287be961f3d8598?quoteToken=token0&quoteCurrency=TOKEN
  const usd_per_weth = encodedScalar(ethers.utils.parseUnits("2150", 30));
  const ohm_per_weth = encodedScalar(ethers.utils.parseUnits("0.010465", 30));
  const usd_per_ohm = encodedMulPrice(usd_per_weth, ohm_per_weth);

  // @todo Should be updated when there's a Chainlink oracle
  const usd_per_usds = encodedScalar(ethers.utils.parseUnits("0.9999", 30));

  return {
    usdsToUsd: usd_per_usds,
    ethToUsd: usd_per_weth,
    ohmToUsd: usd_per_ohm,
    gohmToUsd: encodedMulPrice(encodedTokenPrice(ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN), ohm_per_gohm),   
    vaultToUsd: encodedTokenizedBalanceSheetTokenPrice(ADDRS.VAULTS.hOHM.TOKEN),
  }
};

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.SKY.USDS_TOKEN,
    encodedPrices.usdsToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.WETH_TOKEN,
    encodedPrices.ethToUsd
  ));

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

async function setupPrices() { 
  return updatePrices(INSTANCES.CORE.TOKEN_PRICES.V4);
}

async function testnetThings() {
  await mine(
    INSTANCES.VAULTS.hOHM.SWEEP_SWAPPER.whitelistRouter(ADDRS.VAULTS.hOHM.DUMMY_DEX_ROUTER, true)
  );
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

  await testnetThings();

  await setupPrices();
}

runAsyncMain(main);
