import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  encodedBalancerV2BptPrice,
  encodedErc4626TokenPrice,
  encodedKodiakIslandPrice,
  encodedMulPrice,
  encodedOraclePrice,
  encodedScalar,
  mine,
  runAsyncMain,
  ZERO_ADDRESS,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { TokenPrices } from '../../../../../typechain';
import { encodedKodiakV3Price, encodedTokenPrice } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { DEFAULT_SETTINGS } from '../../default-settings';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    honeyToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.HONEY_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.HONEY_USD_ORACLE.STALENESS_THRESHOLD
    ),
    usdcToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.USDC_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.USDC_USD_ORACLE.STALENESS_THRESHOLD
    ),
    beraToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.BERA_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WBERA_USD_ORACLE.STALENESS_THRESHOLD
    ),
    wBeraToUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.BERA_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WBERA_USD_ORACLE.STALENESS_THRESHOLD
    ),

    // WBERA/USD * iBGT/WBERA
    iBgtToUsd: encodedMulPrice(
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN),
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.WBERA_IBGT_V3, false)
    ),

    ohmToUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.OHM_HONEY_V3, true),
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN),
    ),
    ohmHoneyLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HONEY_V3),
    byusdToUsd: encodedScalar(ethers.utils.parseUnits("1", 30)),
    byusdHoneyLpToUsd: encodedBalancerV2BptPrice(ADDRS.EXTERNAL.BEX.BALANCER_VAULT, ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD),
    rusdToUsd: encodedMulPrice(
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN),
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.RUSD_HONEY_V3, false)
    ),
    rusdHoneyLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.RUSD_HONEY_V3),
    iberaToUsd: encodedMulPrice(
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN),
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.IBERA_WBERA_V3, false)
    ),
    wberaIberaLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBERA_V3),
    wberaHoneyLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_HONEY_V3),
    wberaIbgtLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBGT_V3),

    oriBgtToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.ORIBGT.TOKEN),
    boycoUsdcAToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.BOYCO_USDC_A.TOKEN),
    oacOhmHoneyToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.TOKEN),
    oacByusdHoneyToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.TOKEN),
    oacRusdHoneyToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.TOKEN),
    oacWberaIberaToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.TOKEN),
    oacWberaHoneyToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.TOKEN),
    oacWberaIBgtToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.TOKEN),

    osBgt_toUsd: encodedTokenPrice(ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN),
    iberaOsbgtLpToUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.IBERA_OSBGT_V3),
    oacIberaOsbgtToUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_OSBGT_A.TOKEN),
  }
);

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
    encodedPrices.honeyToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.CIRCLE.USDC_TOKEN,
    encodedPrices.usdcToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ZERO_ADDRESS,
    encodedPrices.beraToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.BERACHAIN.WBERA_TOKEN,
    encodedPrices.wBeraToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.INFRARED.IBGT_TOKEN,
    encodedPrices.iBgtToUsd
  ));
  
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN,
    encodedPrices.ohmToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HONEY_V3,
    encodedPrices.ohmHoneyLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN,
    encodedPrices.byusdToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.BEX.LP_TOKENS.HONEY_BYUSD,
    encodedPrices.byusdHoneyLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.RESERVIOR.RUSD_TOKEN,
    encodedPrices.rusdToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.RUSD_HONEY_V3,
    encodedPrices.rusdHoneyLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.INFRARED.IBERA_TOKEN,
    encodedPrices.iberaToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBERA_V3,
    encodedPrices.wberaIberaLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_HONEY_V3,
    encodedPrices.wberaHoneyLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WBERA_IBGT_V3,
    encodedPrices.wberaIbgtLpToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.ORIBGT.TOKEN,
    encodedPrices.oriBgtToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
    encodedPrices.boycoUsdcAToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.TOKEN,
    encodedPrices.oacOhmHoneyToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.TOKEN,
    encodedPrices.oacByusdHoneyToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.TOKEN,
    encodedPrices.oacRusdHoneyToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.TOKEN,
    encodedPrices.oacWberaIberaToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.TOKEN,
    encodedPrices.oacWberaHoneyToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.TOKEN,
    encodedPrices.oacWberaIBgtToUsd
  ));

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.OPENSTATE.OSBGT_TOKEN,
    encodedPrices.osBgt_toUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.IBERA_OSBGT_V3,
    encodedPrices.iberaOsbgtLpToUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_OSBGT_A.TOKEN,
    encodedPrices.oacIberaOsbgtToUsd
  ));
}

async function main() {
  ({INSTANCES, ADDRS} = await getDeployContext(__dirname));

  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V5);

  await mine(INSTANCES.CORE.TOKEN_PRICES.V5.transferOwnership(ADDRS.CORE.MULTISIG));
}

runAsyncMain(main);
