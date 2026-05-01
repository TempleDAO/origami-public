import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { DEFAULT_SETTINGS } from '../default-settings';
import { seedAutoCompoundingVaultMsig, seedAutoStakingVaultMsig } from '../factory-creators';
import { createSafeBatch, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const autoCompoundingSeed1 = await seedAutoCompoundingVaultMsig(
      owner,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WETH_A.TOKEN,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WETH,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_WETH.SEED_DEPOSIT_SIZE,
      ADDRS.CORE.MULTISIG,
    );
    const autoCompoundingSeed2 = await seedAutoCompoundingVaultMsig(
      owner,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WETH_WBERA_A.TOKEN,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WETH_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WETH_WBERA.SEED_DEPOSIT_SIZE,
      ADDRS.CORE.MULTISIG,
    );
    const autoCompoundingSeed3 = await seedAutoCompoundingVaultMsig(
      owner,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_HONEY_A.TOKEN,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_HONEY.SEED_DEPOSIT_SIZE,
      ADDRS.CORE.MULTISIG,
    );
    const autoCompoundingSeed4 = await seedAutoCompoundingVaultMsig(
      owner,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_WBTC_WBERA_A.TOKEN,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBTC_WBERA.SEED_DEPOSIT_SIZE,
      ADDRS.CORE.MULTISIG,
    );

    const autoStakingSeed1 = await seedAutoStakingVaultMsig(
      owner, 
      ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_WETH_A.VAULT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WETH,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.WBTC_WETH.SEED_DEPOSIT_SIZE,
    );
    const autoStakingSeed2 = await seedAutoStakingVaultMsig(
      owner, 
      ADDRS.VAULTS.INFRARED_AUTO_STAKING_WETH_WBERA_A.VAULT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WETH_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.WETH_WBERA.SEED_DEPOSIT_SIZE,
    );
    const autoStakingSeed3 = await seedAutoStakingVaultMsig(
      owner, 
      ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_HONEY_A.VAULT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.WBTC_HONEY.SEED_DEPOSIT_SIZE,
    );
    const autoStakingSeed4 = await seedAutoStakingVaultMsig(
      owner, 
      ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBTC_WBERA_A.VAULT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBTC_WBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.WBTC_WBERA.SEED_DEPOSIT_SIZE,
    );

    const filename = path.join(__dirname, "./03-seed.json");
    writeSafeTransactionsBatch(
      createSafeBatch([
        ...autoCompoundingSeed1,
        ...autoStakingSeed1,
        ...autoCompoundingSeed2,
        ...autoStakingSeed2,
        ...autoCompoundingSeed3,
        ...autoStakingSeed3,
        ...autoCompoundingSeed4,
        ...autoStakingSeed4,
      ]),
    filename
  );
    
}

runAsyncMain(main);
