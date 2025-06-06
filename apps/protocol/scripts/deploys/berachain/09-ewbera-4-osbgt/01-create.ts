import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { DEFAULT_SETTINGS } from '../default-settings';
import { createAutoStakerSafeTx, createKodiakAutoCompounderSafeTx } from '../factory-creators';
import { createSafeBatch, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const batch: SafeTransaction[] = [
    createKodiakAutoCompounderSafeTx(
      ADDRS,
      INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.EWBERA_4_OSBGT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.EWBERA_4_OSBGT,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_EWBERA_4_OSBGT_A.OVERLORD_WALLET
    ),
    await createAutoStakerSafeTx(
      owner,
      INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.EWBERA_4_OSBGT,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.PERFORMANCE_FEE,
    ),
  ];

  const filename = path.join(__dirname, "./01-create.json");
  writeSafeTransactionsBatch(
    createSafeBatch(batch),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
