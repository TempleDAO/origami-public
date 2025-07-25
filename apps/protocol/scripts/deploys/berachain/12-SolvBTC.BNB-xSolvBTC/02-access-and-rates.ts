import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, encodedKodiakV3Price, encodedMulPrice, encodedTokenPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    wbtc_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.WBTC_HONEY_V3, true), // HONEY per WBTC
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN), // USD per HONEY
    ),

    solvbtc_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.SOLVBTC_WBTC_V3, true), // WBTC per SOLVBTC
      encodedTokenPrice(ADDRS.EXTERNAL.BITCOIN.WBTC_TOKEN), // USD per WBTC
    ),

    xsolvbtc_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.SOLVBTC_XSOLVBTC_V3, true), // SOLVBTC per XSOLVBTC
      encodedTokenPrice(ADDRS.EXTERNAL.SOLV.SOLVBTC_TOKEN), // USD per SOLVBTC
    ),

    solvbtcbnb_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.SOLVBTCBNB_SOLVBTC_V3, true), // SOLVBTC per SOLVBTCBNB
      encodedTokenPrice(ADDRS.EXTERNAL.SOLV.SOLVBTC_TOKEN), // USD per SOLVBTC
    ),

    solvbtcbnb_solvbtc_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.SOLVBTCBNB_SOLVBTC_V3),
    solvbtcbnb_xsolvbtc_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.SOLVBTCBNB_XSOLVBTC_V3),
    oac_solvbtcbnb_xsolvbtc_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.TOKEN),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.BITCOIN.WBTC_TOKEN,
      encodedPrices.wbtc_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.SOLV.SOLVBTC_TOKEN,
      encodedPrices.solvbtc_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.SOLV.XSOLVBTC_TOKEN,
      encodedPrices.xsolvbtc_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.SOLV.SOLVBTCBNB_TOKEN,
      encodedPrices.solvbtcbnb_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.SOLVBTCBNB_SOLVBTC_V3,
      encodedPrices.solvbtcbnb_solvbtc_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.SOLVBTCBNB_XSOLVBTC_V3,
      encodedPrices.solvbtcbnb_xsolvbtc_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.TOKEN,
      encodedPrices.oac_solvbtcbnb_xsolvbtc_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_SOLVBTCBNB_XSOLVBTC_A.VAULT),
      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
