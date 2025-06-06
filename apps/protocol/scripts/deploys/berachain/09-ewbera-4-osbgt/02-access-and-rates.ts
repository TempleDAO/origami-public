import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    eWbera4_toUsd: encodedErc4626TokenPrice(ADDRS.EXTERNAL.EULER_V2.MARKETS.TULIPA_FOLDING_HIVE.VAULTS.WBERA),
    eWbera4_osBgt_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.EWBERA_4_OSBGT_V3),
    oac_eWbera4_osBgt_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.TOKEN),
  }
);

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.EULER_V2.MARKETS.TULIPA_FOLDING_HIVE.VAULTS.WBERA,
      encodedPrices.eWbera4_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.EWBERA_4_OSBGT_V3,
      encodedPrices.eWbera4_osBgt_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.TOKEN,
      encodedPrices.oac_eWbera4_osBgt_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const filename = path.join(__dirname, "./02-access-and-rates.json");
  writeSafeTransactionsBatch(
    createSafeBatch([
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.TOKEN),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.MANAGER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.SWAPPER),
      acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_EWBERA_4_OSBGT_A.VAULT),
      ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
    ]),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
