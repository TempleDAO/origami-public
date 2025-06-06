import '@nomiclabs/hardhat-ethers';
import { mine, runAsyncMain } from '../../../helpers';
import { getDeployContext } from '../../deploy-context';
import { 
  IERC20Metadata__factory,
  IInfraredVault__factory,
    OrigamiInfraredAutoCompounderFactory,
} from '../../../../../typechain';
import { DEFAULT_SETTINGS } from '../../default-settings';
import { BigNumber, ethers } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const RECEIVER = '0x6feb7be522DB641A5C0f246924D8a92cF3218692';

async function seedVault(
  owner: SignerWithAddress,
  factory: OrigamiInfraredAutoCompounderFactory,
  infraredRewardVaultAddress: string,
  seedDepositSize: BigNumber,
) {
  const infraredRewardVault = IInfraredVault__factory.connect(infraredRewardVaultAddress, owner);
  const asset = IERC20Metadata__factory.connect(await infraredRewardVault.stakingToken(), owner);
  await mine(asset.approve(factory.address, seedDepositSize));
  await mine(factory.seedVault(asset.address, seedDepositSize, RECEIVER, ethers.constants.MaxUint256));
}

async function main() {
    const { owner, ADDRS, INSTANCES } = await getDeployContext(__dirname);
    const factory = INSTANCES.FACTORIES.INFRARED_AUTO_COMPOUNDER.FACTORY;

    // OHM/HONEY
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.OHM_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.OHM_HONEY.SEED_DEPOSIT_SIZE,
    );
    
    // BYUSD/HONEY
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.BYUSD_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.BYUSD_HONEY.SEED_DEPOSIT_SIZE,
    );

    // rUSD/HONEY
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.RUSD_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.RUSD_HONEY.SEED_DEPOSIT_SIZE,
    );

    // WBERA/iBERA
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBERA_IBERA,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBERA_IBERA.SEED_DEPOSIT_SIZE,
    );

    // WBERA/HONEY
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBERA_HONEY,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBERA_HONEY.SEED_DEPOSIT_SIZE,
    );

    // WBERA/IBGT
    await seedVault(
      owner,
      factory,
      ADDRS.EXTERNAL.INFRARED.REWARD_VAULTS.WBERA_IBGT,
      DEFAULT_SETTINGS.VAULTS.INFRARED_AUTO_COMPOUNDERS.WBERA_IBGT.SEED_DEPOSIT_SIZE,
    );
}

runAsyncMain(main);
