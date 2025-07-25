import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    ibera4_ibgt_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.IBERA_IBGT_V3),
    oac_ibera_ibgt_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.TOKEN),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.IBERA_IBGT_V3,
      encodedPrices.ibera4_ibgt_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.TOKEN,
      encodedPrices.oac_ibera_ibgt_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_IBERA_IBGT_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_IBERA_IBGT_A.VAULT),
      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
