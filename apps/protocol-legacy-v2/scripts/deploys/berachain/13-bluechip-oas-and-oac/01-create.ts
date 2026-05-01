import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { DEFAULT_SETTINGS } from '../default-settings';
import { createAutoStakerSafeTx, createKodiakAutoCompounderSafeTx } from '../factory-creators';
import { createSafeBatch, SafeTransaction, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
  const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  const batchA: SafeTransaction[] = [
    createKodiakAutoCompounderSafeTx(
      ADDRS,
      INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_WETH,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WETH,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.OVERLORD_WALLET
    ),
    await createAutoStakerSafeTx(
      owner,
      INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WETH,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.PERFORMANCE_FEE,
    ),
  ];

  const batchB: SafeTransaction[] = [
    createKodiakAutoCompounderSafeTx(
      ADDRS,
      INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WETH_WBERA,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WETH_WBERA,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.OVERLORD_WALLET
    ),
    await createAutoStakerSafeTx(
      owner,
      INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WETH_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.PERFORMANCE_FEE,
    ),
  ];

  const batchC: SafeTransaction[] = [
    createKodiakAutoCompounderSafeTx(
      ADDRS,
      INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_HONEY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_HONEY,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.OVERLORD_WALLET
    ),
    await createAutoStakerSafeTx(
      owner,
      INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.PERFORMANCE_FEE,
    ),
  ];

  const batchD: SafeTransaction[] = [
    createKodiakAutoCompounderSafeTx(
      ADDRS,
      INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_WBERA,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WBERA,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.OVERLORD_WALLET
    ),
    await createAutoStakerSafeTx(
      owner,
      INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.PERFORMANCE_FEE,
    ),
  ];

  let filename = path.join(__dirname, "./01-create-a.json");
  writeSafeTransactionsBatch(
    createSafeBatch(batchA),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);

  filename = path.join(__dirname, "./01-create-b.json");
  writeSafeTransactionsBatch(
    createSafeBatch(batchB),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);

  filename = path.join(__dirname, "./01-create-c.json");
  writeSafeTransactionsBatch(
    createSafeBatch(batchC),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);

  filename = path.join(__dirname, "./01-create-d.json");
  writeSafeTransactionsBatch(
    createSafeBatch(batchD),
    filename
  );
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
