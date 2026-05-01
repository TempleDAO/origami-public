import '@nomiclabs/hardhat-ethers';
import { ethers } from 'hardhat';
import {
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { getDeployContext } from '../../deploy-context';
import { ContractAddresses } from '../../contract-addresses/types';

let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;

async function dumpPrices() {
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V5.tokenPrices([
    ADDRS.EXTERNAL.OLYMPUS.OHM_TOKEN,
    ADDRS.VAULTS.hOHM.TOKEN,
    ADDRS.EXTERNAL.KODIAK.ISLANDS.OHM_HOHM_V3,
  ]);
  console.log("Token Prices ($):");
  console.log("\tOHM:", ethers.utils.formatUnits(prices[0], 30));
  console.log("\thOHM:", ethers.utils.formatUnits(prices[1], 30));
  console.log("\tOHM/hOHM Island:", ethers.utils.formatUnits(prices[2], 30));
}

async function main() {
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));
  
  await dumpPrices();
}

runAsyncMain(main);
