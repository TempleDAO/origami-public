import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { acceptOwner, createSafeBatch, writeSafeTransactionsBatch } from '../../../safe-tx-builder';
import path from 'path';
import { network } from 'hardhat';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const batch = createSafeBatch(
      [
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC),
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.BERA_BGT_PROXY),
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN),
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER),
      ],
    );
          
    const filename = path.join(__dirname, "./transactions-batch.json");
    writeSafeTransactionsBatch(batch, filename);
    console.log(`Wrote Safe tx's batch to: ${filename}`);
  }
}

runAsyncMain(main);
