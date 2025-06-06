import '@nomiclabs/hardhat-ethers';
import {
  mine,
  runAsyncMain,
} from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { acceptOwner, appendTransactionsToBatch } from '../../../safe-tx-builder';
import path from 'path';
import { network } from 'hardhat';

async function main() {
  const {ADDRS, INSTANCES} = await getDeployContext(__dirname);

  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD.proposeNewOwner(ADDRS.CORE.MULTISIG)); // @todo still
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN.proposeNewOwner(ADDRS.CORE.MULTISIG));
  await mine(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER.proposeNewOwner(ADDRS.CORE.MULTISIG));

  if (network.name != "localhost") {
    const filename = path.join(__dirname, "../transactions-batch.json");
    appendTransactionsToBatch(
      filename,
      [
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_USDC),
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.INFRARED_REWARDS_VAULT_PROXIES.HONEY_BYUSD), // @todo still
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.TOKEN),
        acceptOwner(INSTANCES.VAULTS.BOYCO_USDC_A.MANAGER),
      ],
    );
  }
}

runAsyncMain(main);
