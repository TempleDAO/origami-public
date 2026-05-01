import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    swbera_toUsd: encodedErc4626TokenPrice(ADDRS.EXTERNAL.BERACHAIN.SWBERA_TOKEN),
    swbera_osbgt_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.SWBERA_OSBGT_V3),
    oac_swbera_osBgt_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.TOKEN.address),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.BERACHAIN.SWBERA_TOKEN,
      encodedPrices.swbera_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.SWBERA_OSBGT_V3,
      encodedPrices.swbera_osbgt_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.TOKEN.address,
      encodedPrices.oac_swbera_osBgt_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.TOKEN.address),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SWBERA_OSBGT_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_SWBERA_OSBGT_A.VAULT.address),
      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
