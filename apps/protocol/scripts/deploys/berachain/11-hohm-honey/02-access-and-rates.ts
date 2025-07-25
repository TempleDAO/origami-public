import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, encodedKodiakV3Price, encodedMulPrice, encodedTokenPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    // hOHM/HONEY / HONEY/USD
    hOHM_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.HOHM_HONEY_V3, true), // HONEY per hOHM
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN), // USD per HONEY
    ),
    hohm_honey_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.HOHM_HONEY_V3),
    oac_hohm_honey_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.TOKEN),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.VAULTS.hOHM.TOKEN,
      encodedPrices.hOHM_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.HOHM_HONEY_V3,
      encodedPrices.hohm_honey_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.TOKEN,
      encodedPrices.oac_hohm_honey_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_HOHM_HONEY_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_HOHM_HONEY_A.VAULT),
      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
