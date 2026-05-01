import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, encodedKodiakV3Price, encodedMulPrice, encodedOraclePrice, encodedTokenPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';
import { DEFAULT_SETTINGS } from '../default-settings';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    weth_toUsd: encodedOraclePrice(
      ADDRS.EXTERNAL.REDSTONE.ETH_USD_ORACLE,
      DEFAULT_SETTINGS.EXTERNAL.REDSTONE.WETH_USD_ORACLE.STALENESS_THRESHOLD
    ),

    wbtc_weth_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_WETH_V3),
    weth_wbera_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_WBERA_V3),
    wbtc_honey_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_HONEY_V3),
    wbtc_wbera_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_WBERA_V3),

    oac_wbtc_weth_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.TOKEN),
    oac_weth_wbera_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.TOKEN),
    oac_wbtc_honey_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.TOKEN),
    oac_wbtc_wbera_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.TOKEN),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.ETHEREUM.WETH_TOKEN,
      encodedPrices.weth_toUsd
    ),

    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_WETH_V3,
      encodedPrices.wbtc_weth_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_WBERA_V3,
      encodedPrices.weth_wbera_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_HONEY_V3,
      encodedPrices.wbtc_honey_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.WBTC_WBERA_V3,
      encodedPrices.wbtc_wbera_toUsd
    ),

    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.TOKEN,
      encodedPrices.oac_wbtc_weth_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.TOKEN,
      encodedPrices.oac_weth_wbera_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.TOKEN,
      encodedPrices.oac_wbtc_honey_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.TOKEN,
      encodedPrices.oac_wbtc_wbera_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_WETH_A.VAULT),

      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WETH_WBERA_A.VAULT),

      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_HONEY_A.VAULT),

      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_WBERA_A.VAULT),

      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
