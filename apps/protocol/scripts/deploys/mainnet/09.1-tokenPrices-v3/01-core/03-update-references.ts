import '@nomiclabs/hardhat-ethers';
import { ethers, network } from 'hardhat';
import {
  ensureExpectedEnvvars,
  impersonateAndFund,
  mine,
} from '../../../helpers';
import { ContractInstances, connectToContracts, getDeployedContracts } from '../../contract-addresses';
import { ContractAddresses } from '../../contract-addresses/types';
import { createSafeBatch, setTokenPrices, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { Signer } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

let ADDRS: ContractAddresses;
let INSTANCES: ContractInstances;

async function updateTokenPrices(owner: Signer) {
  await mine(INSTANCES.LOV_SUSDE_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_SUSDE_B.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_USDE_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_USDE_B.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_WEETH_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_EZETH_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_WSTETH_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
  await mine(INSTANCES.LOV_WOETH_A.TOKEN.setTokenPrices(ADDRS.CORE.TOKEN_PRICES.V3));
}
  
async function updateTokenPricesSafeBatch() {
  const batch = createSafeBatch(
    1,
    [
      setTokenPrices(INSTANCES.LOV_SUSDE_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_SUSDE_B.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_USDE_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_USDE_B.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_WEETH_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_EZETH_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_WSTETH_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
      setTokenPrices(INSTANCES.LOV_WOETH_A.TOKEN, ADDRS.CORE.TOKEN_PRICES.V3),
    ],
  );

  const filename = path.join(__dirname, "../transactions-batch.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

// Required for testnet run to impersonate the msig
async function setupTokenPricesTestnet(owner: SignerWithAddress) { 
  const signer = await impersonateAndFund(owner, ADDRS.CORE.MULTISIG);
  await updateTokenPrices(signer);
}

async function setupTokenPricesProdnet() { 
  updateTokenPricesSafeBatch();
}
  
async function main() {
  ensureExpectedEnvvars();
  
  const [owner] = await ethers.getSigners();
  ADDRS = getDeployedContracts();
  INSTANCES = connectToContracts(owner);
  
  if (network.name === "localhost") {
    await setupTokenPricesTestnet(owner);
  } else {
    await setupTokenPricesProdnet();
  }
}
  
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
