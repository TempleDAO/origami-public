import '@nomiclabs/hardhat-ethers';
import { network } from 'hardhat';
import {
  mine,
  runAsyncMain,
} from '../../helpers';
import { ContractAddresses } from '../contract-addresses/types';
import { OrigamiDelegated4626Vault, OrigamiDelegated4626Vault__factory } from '../../../../typechain';
import { getDeployContext } from '../deploy-context';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { impersonateAndFund } from '../../helpers';
import { createSafeBatch, setTokenPrices, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';
import { JsonRpcSigner } from '@ethersproject/providers';

let ADDRS: ContractAddresses;
let OWNER: SignerWithAddress;
let CONTRACTS_TO_UPGRADE: OrigamiDelegated4626Vault[];

async function updateTokenPrices(signer: JsonRpcSigner) {
  for await (const contract of CONTRACTS_TO_UPGRADE) {
    await mine(contract.connect(signer).setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V5));
  }
}
  
async function updateTokenPricesSafeBatch() {
  const batch = createSafeBatch(
    CONTRACTS_TO_UPGRADE.map(contract => setTokenPrices(contract, ADDRS.CORE.TOKEN_PRICES.V5))
  );

  const filename = path.join(__dirname, "./transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

// Required for testnet run to impersonate the msig
async function setupTokenPricesTestnet() { 
  const signer = await impersonateAndFund(OWNER, ADDRS.CORE.MULTISIG);
  await updateTokenPrices(signer);
}

async function setupTokenPricesProdnet() { 
  updateTokenPricesSafeBatch();
}
  
async function main() {
  ({owner: OWNER, ADDRS} = await getDeployContext(__dirname));

  console.log(ADDRS.CORE.TOKEN_PRICES.V5);

  const addressesToUpdate = [
    ADDRS.VAULTS.BOYCO_USDC_A.TOKEN,
    ADDRS.VAULTS.ORIBGT.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_OHM_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_BYUSD_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_RUSD_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBERA_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_HONEY_A.TOKEN,
    ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBERA_IBGT_A.TOKEN,
    ADDRS.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
  ];

  CONTRACTS_TO_UPGRADE = addressesToUpdate.map(address => OrigamiDelegated4626Vault__factory.connect(address, OWNER));

  if (network.name === "localhost") {
    await setupTokenPricesTestnet();
  } else {
    await setupTokenPricesProdnet();
  }
}

runAsyncMain(main);
