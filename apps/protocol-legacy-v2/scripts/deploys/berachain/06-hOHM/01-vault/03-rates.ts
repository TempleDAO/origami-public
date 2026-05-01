import '@nomiclabs/hardhat-ethers';
import { encodedKodiakIslandPrice, encodedKodiakV3Price, encodedMulPrice, encodedTokenPrice, impersonateAndFund2, mine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { ContractAddresses } from '../../contract-addresses/types';
import { TokenPrices } from '../../../../../typechain';
import { createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { ContractInstances } from '../../contract-addresses';
import { network } from 'hardhat';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

const getEncodedPrices = () => (
  {
    // hOHM/OHM * OHM/USD
    hOHM_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.OHM_HOHM_V3, false),
      encodedTokenPrice(ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN),
    ),
    ohm_hohm_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HOHM_V3),
  }
);

function updatePricesSafeBatch(contract: TokenPrices): SafeTransaction[] {
  const encodedPrices = getEncodedPrices();

  return [
    setTokenPriceFunction(contract, ADDRS.VAULTS.hOHM.TOKEN,
      encodedPrices.hOHM_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HOHM_V3,
      encodedPrices.ohm_hohm_LP_toUsd
    ),
  ];
}

async function updatePrices(contract: TokenPrices) {
  const encodedPrices = getEncodedPrices();

  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.hOHM.TOKEN,
    encodedPrices.hOHM_toUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HOHM_V3,
    encodedPrices.ohm_hohm_LP_toUsd
  ));
}

// Required for testnet run to impersonate the msig
async function setupPricesTestnet() { 
  const signer = await impersonateAndFund2(ADDRS.CORE.MULTISIG);
  await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V5.connect(signer));
}

async function main() {
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

  if (network.name === "localhost") {
    await setupPricesTestnet();
  } else { 
    const filename = path.join(__dirname, "./03-rates.json");
    writeSafeTransactionsBatch(
      createSafeBatch(updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5)),
      filename
    );
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
