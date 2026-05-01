import '@nomiclabs/hardhat-ethers';
import { runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { DEFAULT_SETTINGS } from '../default-settings';
import { seedAutoCompoundingVaultMsig, seedAutoStakingVaultMsig } from '../factory-creators';
import { createSafeBatch, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
    const { owner, ADDRS } = await getDeployContext(__dirname);

    const autoCompoundingSeed = await seedAutoCompoundingVaultMsig(
      owner,
      ADDRS.VAULTS.INFRARED_AUTO_COMPOUNDER_SOLVBTCBNB_XSOLVBTC_A.TOKEN,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.SOLVBTCBNB_XSOLVBTC,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.SOLVBTCBNB_XSOLVBTC.SEED_DEPOSIT_SIZE,
      ADDRS.CORE.MULTISIG,
    );

    const autoStakingSeed = await seedAutoStakingVaultMsig(
      owner, 
      ADDRS.VAULTS.INFRARED_AUTO_STAKING_SOLVBTCBNB_XSOLVBTC_A.VAULT,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.SOLVBTCBNB_XSOLVBTC,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_STAKING.SOLVBTCBNB_XSOLVBTC.SEED_DEPOSIT_SIZE,
    );

    const filename = path.join(__dirname, "./03-seed.json");
    writeSafeTransactionsBatch(
      createSafeBatch([
        ...autoCompoundingSeed,
        ...autoStakingSeed,
      ]),
    filename
  );
    
}

runAsyncMain(main);
