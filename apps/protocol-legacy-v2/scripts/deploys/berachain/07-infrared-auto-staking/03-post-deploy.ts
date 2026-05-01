import '@nomiclabs/hardhat-ethers';
import { mine, runAsyncMain } from '../../helpers';
import { getDeployContext } from '../deploy-context';
import { OrigamiAutoStaking__factory, OrigamiAutoStakingFactory__factory, } from '../../../../typechain';
import { acceptOwner, createSafeBatch, writeSafeTransactionsBatch } from '../../safe-tx-builder';
import path from 'path';

async function main() {
  const { owner: OWNER, ADDRS, INSTANCES } = await getDeployContext(__dirname);

  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_OHM_HONEY_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_RUSD_HONEY_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_IBERA_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_HONEY_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_IBGT_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  await mine(OrigamiAutoStakingFactory__factory.connect(ADDRS.FACTORIES.INFRARED_AUTO_STAKING.FACTORY, OWNER)['proposeNewOwner(address,address)'](
    ADDRS.VAULTS.INFRARED_AUTO_STAKING_IBERA_OSBGT_A.VAULT,
    ADDRS.CORE.MULTISIG
  ));
  
  const batch = createSafeBatch(
    [
      acceptOwner(INSTANCES.FACTORIES.INFRARED_AUTO_STAKING.FACTORY),

      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_OHM_HONEY_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_BYUSD_HONEY_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_RUSD_HONEY_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_IBERA_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_HONEY_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_WBERA_IBGT_A.VAULT, OWNER)),
      acceptOwner(OrigamiAutoStaking__factory.connect(ADDRS.VAULTS.INFRARED_AUTO_STAKING_IBERA_OSBGT_A.VAULT, OWNER)),
    ],
  );
  
  const filename = path.join(__dirname, "./03-post-deploy.json");
  writeSafeTransactionsBatch(batch, filename);
  console.log(`Wrote Safe tx's batch to: ${filename}`);
}

runAsyncMain(main);
