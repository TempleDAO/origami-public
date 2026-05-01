import '@nomiclabs/hardhat-ethers';
import { encodedErc4626TokenPrice, encodedKodiakIslandPrice, mine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { ContractAddresses } from '../contract-addresses/types';
import { TokenPrices } from '../../../../typechain';
import { acceptOwnerAddr, createSafeBatch, SafeTransaction, setTokenPriceFunction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';
import { ethers, network } from 'hardhat';

const getEncodedPrices = (ADDRS: ContractAddresses) => (
  {
    weth_honey_LP_toUsd: encodedKodiakIslandPrice(ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_HONEY_V3),
    oac_weth_honey_toUsd: encodedErc4626TokenPrice(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.TOKEN.address),
  }
);

async function updatePrices(contract: TokenPrices, ADDRS: ContractAddresses) {
  const encodedPrices = getEncodedPrices(ADDRS);

  await mine(contract.setTokenPriceFunction(
    ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_HONEY_V3,
    encodedPrices.weth_honey_LP_toUsd
  ));
  await mine(contract.setTokenPriceFunction(
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.TOKEN.address,
    encodedPrices.oac_weth_honey_toUsd
  ));
}

function updatePricesSafeBatch(contract: TokenPrices, ADDRS: ContractAddresses): SafeTransaction[] {
  const encodedPrices = getEncodedPrices(ADDRS);

  return [
    setTokenPriceFunction(contract, ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_HONEY_V3,
      encodedPrices.weth_honey_LP_toUsd
    ),
    setTokenPriceFunction(contract, ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.TOKEN.address,
      encodedPrices.oac_weth_honey_toUsd
    ),
  ];
}

async function main() {
  const { ADDRS, INSTANCES } = await getDeployContext(__dirname);

  if (network.name === "localhost") {
    await updatePrices(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS);

    const prices = await INSTANCES.CORE.TOKEN_PRICES.V5.tokenPrices([
      ADDRS.EXTERNAL.ETHEREUM.WETH_TOKEN,
      ADDRS.EXTERNAL.BERACHAIN.HONEY_TOKEN,
      ADDRS.EXTERNAL.KODIAK.ISLANDS.WETH_HONEY_V3,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.TOKEN.address,
    ]);
    console.log("WETH:", ethers.utils.formatUnits(prices[0], 30));
    console.log("HONEY:", ethers.utils.formatUnits(prices[1], 30));
    console.log("ISLANDS.WETH_HONEY_V3:", ethers.utils.formatUnits(prices[2], 30));
    console.log("oAC-WETH-HONEY-A:", ethers.utils.formatUnits(prices[3], 30));
  } else {
    const filename = path.join(__dirname, "./02-access-and-rates.json");
    writeSafeTransactionsBatch(
      createSafeBatch([
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.TOKEN.address),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.MANAGER),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_HONEY_A.SWAPPER),
        acceptOwnerAddr(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WETH_HONEY_A.VAULT.address),
        ...updatePricesSafeBatch(INSTANCES.CORE.TOKEN_PRICES.V5, ADDRS),
      ]),
      filename
    );
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
