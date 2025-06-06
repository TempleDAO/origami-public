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
    INSTANCES.LOV_SUSDE_A.TOKEN,
    INSTANCES.LOV_SUSDE_B.TOKEN,
    INSTANCES.LOV_USDE_A.TOKEN,
    INSTANCES.LOV_USDE_B.TOKEN,
    INSTANCES.LOV_WEETH_A.TOKEN,
    INSTANCES.LOV_EZETH_A.TOKEN,
    INSTANCES.LOV_WSTETH_A.TOKEN,
    INSTANCES.LOV_WOETH_A.TOKEN,

    INSTANCES.LOV_WETH_DAI_LONG_A.TOKEN,
    INSTANCES.LOV_WBTC_DAI_LONG_A.TOKEN,
    INSTANCES.LOV_WETH_WBTC_LONG_A.TOKEN,
    INSTANCES.LOV_WETH_SDAI_SHORT_A.TOKEN,
    INSTANCES.LOV_WBTC_SDAI_SHORT_A.TOKEN,
    INSTANCES.LOV_WETH_WBTC_SHORT_A.TOKEN,
    INSTANCES.LOV_PT_SUSDE_OCT24_A.TOKEN,
    INSTANCES.LOV_USD0pp_A.TOKEN,
    INSTANCES.LOV_WSTETH_B.TOKEN,
    INSTANCES.LOV_AAVE_USDC_LONG_A.TOKEN,
    INSTANCES.LOV_SDAI_A.TOKEN,
    INSTANCES.LOV_RSWETH_A.TOKEN,
    INSTANCES.LOV_PT_EBTC_DEC24_A.TOKEN,
    INSTANCES.LOV_PT_CORN_LBTC_DEC24_A.TOKEN,
    INSTANCES.LOV_WETH_CBBTC_LONG_A.TOKEN,
    INSTANCES.VAULTS.SUSDSpS.TOKEN,
    INSTANCES.LOV_PT_SUSDE_MAR_2025_A.TOKEN,
    INSTANCES.LOV_PT_USD0pp_MAR_2025_A.TOKEN,
    INSTANCES.LOV_PT_LBTC_MAR_2025_A.TOKEN,
    INSTANCES.LOV_PT_SUSDE_MAY_2025_A.TOKEN,
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
