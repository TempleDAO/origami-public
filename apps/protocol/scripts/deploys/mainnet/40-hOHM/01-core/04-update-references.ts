import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import {
  impersonateAndFund2,
  mine,
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { createSafeBatch, setTokenPrices, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { Contract } from 'ethers';
import { getDeployContext } from '../../deploy-context';
import { JsonRpcSigner } from '@ethersproject/providers';

let INSTANCES: ContractInstances;
let ADDRS: ContractAddresses;
let TOKEN_PRICES_ADDRESS: string;

function getInstancesToUpdate() {
  return [
    // INSTANCES.LOV_SUSDE_A.TOKEN,
    // ...
  ];
}

async function mineUpdateTokenPrices(contract: Contract, signer: JsonRpcSigner) {
  await mine(contract.connect(signer).setTokenPrices(TOKEN_PRICES_ADDRESS));
}

async function updateTokenPrices(signer: JsonRpcSigner) {
  const instances = getInstancesToUpdate();
  for (const instance of instances) {
    await mineUpdateTokenPrices(instance, signer);
  }
}

async function updateTokenPricesSafeBatch() {
  const batch = createSafeBatch(
    getInstancesToUpdate().map(i => setTokenPrices(i, TOKEN_PRICES_ADDRESS))
  );

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}
  
async function main() {
  ({ADDRS, INSTANCES} = await getDeployContext(__dirname));

  TOKEN_PRICES_ADDRESS = ADDRS.CORE.TOKEN_PRICES.V4;
  
  if (network.name === "localhost") {
    const signer = await impersonateAndFund2(ADDRS.CORE.MULTISIG);
    await updateTokenPrices(signer);
  } else {
    updateTokenPricesSafeBatch();
  }
}
  
runAsyncMain(main);
