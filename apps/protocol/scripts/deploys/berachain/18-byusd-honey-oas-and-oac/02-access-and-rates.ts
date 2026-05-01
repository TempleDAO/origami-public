import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, encodedKodiakV3Price, encodedMulPrice, encodedTokenPrice, impersonateAndFund2, mine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';
import { ethers, network } from 'hardhat';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    // [USD/BYUSD]
    byusd_toUsd: encodedMulPrice(
      encodedKodiakV3Price(ADDRS.EXTERNAL.KODIAK.POOLS.BYUSD_HONEY_V3, true), // [HONEY/BYUSD]
      encodedTokenPrice(ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN), // [USD/HONEY]
    ),
    byusd_honey_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.BYUSD_HONEY_V3),
    oac_byusd_honey_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.TOKEN.address),
  }
);

async function updatePrices(contract: TokenPrices, ADDRS: ContractAddresses) {
  const encodedPrices = getEncodedPrices(ADDRS);

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN,
    encodedPrices.byusd_toUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.BYUSD_HONEY_V3,
    encodedPrices.byusd_honey_LP_toUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.TOKEN.address,
    encodedPrices.oac_byusd_honey_toUsd
  ));
}

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN,
      encodedPrices.byusd_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.BYUSD_HONEY_V3,
      encodedPrices.byusd_honey_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.TOKEN.address,
      encodedPrices.oac_byusd_honey_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  if (network.name === "localhost") {
    const signer = await impersonateAndFund2(await INSTANCES.CORE.TOKEN_PRICES.V5.owner());
    const tokenPrices = INSTANCES.CORE.TOKEN_PRICES.V5.connect(signer);

    await updatePrices(tokenPrices, ADDRS);

    const prices = await tokenPrices.tokenPrices([
      ADDRS.EXTERNAL.PAYPAL.BYUSD_TOKEN,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.KODIAK.ISLANDS.BYUSD_HONEY_V3,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.TOKEN.address,
    ]);
    console.log("BYUSD:", ethers.utils.formatUnits(prices[0], 30));
    console.log("HONEY:", ethers.utils.formatUnits(prices[1], 30));
    console.log("ISLANDS.BYUSD_HONEY_V3:", ethers.utils.formatUnits(prices[2], 30));
    console.log("oAC-BYUSD-HONEY-B:", ethers.utils.formatUnits(prices[3], 30));
  } else {
    const filename = path.join(__dirname, "./02-access-and-rates.json");
    writeSafeTransactionsBatch(
      createSafeBatch([
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.TOKEN.address),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.MANAGER),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_B.SWAPPER),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_B.VAULT.address),
        ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
      ]),
      filename
    );
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
