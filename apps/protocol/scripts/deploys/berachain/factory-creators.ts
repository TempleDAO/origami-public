import '@nomiclabs/hardhat-ethers';
import { mine, ZERO_ADDRESS } from '../helpers';
import { 
  IERC20Metadata__factory,
  IInfraredVault,
  IInfraredVault__factory,
    IOrigamiAutoStaking__factory,
    OrigamiAutoStakingFactory,
    OrigamiDelegated4626Vault__factory,
    OrigamiInfraredAutoCompounderFactory,
    OrigamiInfraredVaultManager__factory,
} from '../../../typechain';
import { Address, ContractAddresses } from './contract-addresses/types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, ethers } from 'ethers';
import { approve, createSafeTransaction, SafeTransaction } from '../safe-tx-builder';

interface InfraredAutoCompounderVaultSettings {
  TOKEN_SYMBOL: string;
  TOKEN_NAME: string;
  PERFORMANCE_FEE: number;
}

function seedAutoCompoundingVaultSafeTx(
  contractAddress: string,
  assets: BigNumber,
  receiver: string,
  maxTotalSupply: BigNumber,
) {
  return createSafeTransaction(
    contractAddress,
    "seedDeposit",
    [
      {
        argType: "uint256",
        name: "assets",
        value: assets.toString(),
      },
      {
        argType: "address",
        name: "receiver",
        value: receiver,
      },
      {
        argType: "uint256",
        name: "maxTotalSupply_",
        value: maxTotalSupply.toString(),
      },
    ],
  )
}

export function acceptOwnerSafeTx(
    contractAddress: string
) {
  return createSafeTransaction(
    contractAddress,
    "acceptOwner",
    [],
  )
}

export async function seedAutoCompoundingVaultMsig(
    owner: SignerWithAddress,
    vaultAddress: string,
    infraredRewardVaultAddress: string,
    seedDepositSize: BigNumber,
    receiver: string,
) {
    const infraredRewardVault = IInfraredVault__factory.connect(infraredRewardVaultAddress, owner);
    const asset = IERC20Metadata__factory.connect(await infraredRewardVault.stakingToken(), owner);
    return [
        approve(asset, vaultAddress, seedDepositSize),
        seedAutoCompoundingVaultSafeTx(vaultAddress, seedDepositSize, receiver, ethers.constants.MaxUint256),
    ];
}

export async function seedVault(
  owner: SignerWithAddress,
  factory: OrigamiInfraredAutoCompounderFactory,
  infraredRewardVaultAddress: string,
  seedDepositSize: BigNumber,
  receiver: string,
) {
  const infraredRewardVault = IInfraredVault__factory.connect(infraredRewardVaultAddress, owner);
  const asset = IERC20Metadata__factory.connect(await infraredRewardVault.stakingToken(), owner);
  await mine(asset.approve(factory.address, seedDepositSize));
  await mine(factory.seedVault(asset.address, seedDepositSize, receiver, ethers.constants.MaxUint256));
}

async function logNewAutoCompounders(
  key: string,
  owner: SignerWithAddress,
  factory: OrigamiInfraredAutoCompounderFactory, 
  rewardVault: Address,
) {
  const infraredVault = IInfraredVault__factory.connect(rewardVault, owner);
  const asset = await infraredVault.stakingToken();
  const assetName = await (IERC20Metadata__factory.connect(asset, owner)).name();
  const newVault = OrigamiDelegated4626Vault__factory.connect(
    await factory.registeredVaults(asset),
    owner
  );
  const newManager = OrigamiInfraredVaultManager__factory.connect(
    await newVault.manager(),
    owner
  );
  const newSwapper = await newManager.swapper();
  console.log(`*** New Vault ${key} ***`);
  console.log(`vault asset: ${assetName} (${asset})`);
  console.log(`${key}.TOKEN: ${newVault.address}`);
  console.log(`${key}.MANAGER: ${newManager.address}`);
  console.log(`${key}.SWAPPER: ${newSwapper}`);
  console.log("");
}

export async function createKodiakAutoCompounder(
  key: string,
  owner: SignerWithAddress,
  ADDRS: ContractAddresses,
  factory: OrigamiInfraredAutoCompounderFactory, 
  vaultInstances: InfraredAutoCompounderVaultSettings,
  rewardVault: Address,
  overlordWallet: Address,
) {
  await mine(
    factory.create(
      vaultInstances.TOKEN_NAME,
      vaultInstances.TOKEN_SYMBOL,
      rewardVault,
      vaultInstances.PERFORMANCE_FEE,
      overlordWallet,
      [ADDRS.EXTERNAL.OOGABOOGA.ROUTER, ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER],
    )
  );

  await logNewAutoCompounders(key, owner, factory, rewardVault);
}

export function createKodiakAutoCompounderSafeTx(
  ADDRS: ContractAddresses,
  factory: OrigamiInfraredAutoCompounderFactory, 
  vaultInstances: InfraredAutoCompounderVaultSettings,
  rewardVault: Address,
  overlordWallet: Address,
): SafeTransaction {
  const routers = [
    ADDRS.EXTERNAL.OOGABOOGA.ROUTER,
    ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1,
    ADDRS.EXTERNAL.KODIAK.ISLAND_ROUTER
  ];

  return createSafeTransaction(
    factory.address,
    "create",
    [
      {
        argType: "string",
        name: "name_",
        value: vaultInstances.TOKEN_NAME,
      },
      {
        argType: "string",
        name: "symbol_",
        value: vaultInstances.TOKEN_SYMBOL,
      },
      {
        argType: "contract IInfraredVault",
        name: "infraredRewardVault_",
        value: rewardVault,
      },
      {
        argType: "uint16",
        name: "performanceFeeBps_",
        value: vaultInstances.PERFORMANCE_FEE.toString(),
      },
      {
        argType: "address",
        name: "overlord_",
        value: overlordWallet,
      },
      {
        argType: "address[]",
        name: "expectedSwapRouters_",
        value: `["${routers.join('","')}"]`,
      },
    ],
  );
}

function stakeSafeTx(
  contractAddress: string,
  amount: BigNumber,
) {
  return createSafeTransaction(
    contractAddress,
    "stake",
    [
      {
        argType: "uint256",
        name: "amount",
        value: amount.toString(),
      },
    ],
  )
}

export async function seedAutoStakingVaultMsig(
    owner: SignerWithAddress,
    vaultAddress: string,
    infraredRewardVaultAddress: string,
    seedDepositSize: BigNumber,
) {
    const infraredRewardVault = IInfraredVault__factory.connect(infraredRewardVaultAddress, owner);
    const asset = IERC20Metadata__factory.connect(await infraredRewardVault.stakingToken(), owner);
    return [
        approve(asset, vaultAddress, seedDepositSize),
        stakeSafeTx(vaultAddress, seedDepositSize),
    ];
}

export async function createBexAutoCompounder(
  key: string,
  owner: SignerWithAddress,
  ADDRS: ContractAddresses,
  factory: OrigamiInfraredAutoCompounderFactory, 
  vaultInstances: InfraredAutoCompounderVaultSettings,
  rewardVault: Address,
  overlordWallet: Address,
) {
  await mine(
    factory.create(
      vaultInstances.TOKEN_NAME,
      vaultInstances.TOKEN_SYMBOL,
      rewardVault,
      vaultInstances.PERFORMANCE_FEE,
      overlordWallet,
      [ADDRS.EXTERNAL.OOGABOOGA.ROUTER, ADDRS.EXTERNAL.MAGPIE.ROUTER_V3_1, ADDRS.EXTERNAL.BEX.BALANCER_VAULT],
    )
  );

  await logNewAutoCompounders(key, owner, factory, rewardVault);
}

async function logNewAutoStaking(
  key: string,
  owner: SignerWithAddress,
  factory: OrigamiAutoStakingFactory, 
  infraredVault: IInfraredVault,
) {
  const stakingToken = await infraredVault.stakingToken();
  const stakingTokenName = await (IERC20Metadata__factory.connect(stakingToken, owner)).name();
  const newVault = IOrigamiAutoStaking__factory.connect(
    (await factory.currentVaultForAsset(stakingToken)).vault,
    owner
  );
  const newSwapper = await newVault.swapper();
  console.log(`*** New Vault ${key} ***`);
  console.log(`vault staking token: ${stakingTokenName} (${stakingToken})`);
  console.log(`${key}.VAULT: ${newVault.address}`);
  console.log(`${key}.SWAPPER: ${newSwapper}`);
  console.log("");
}

export async function createAutoStaker(
  key: string,
  owner: SignerWithAddress,
  factory: OrigamiAutoStakingFactory,
  rewardVault: Address,
  performanceFeeBps: number
) {
  const infraredVault = IInfraredVault__factory.connect(rewardVault, owner);

  if ((await factory.swapperDeployer()) != ZERO_ADDRESS) {
    throw Error("Single-reward mode not handled yet");
  }

  await mine(
    factory.registerVault(
      await infraredVault.stakingToken(),
      infraredVault.address,
      performanceFeeBps,
      ZERO_ADDRESS,
      [],
    )
  );

  await logNewAutoStaking(key, owner, factory, infraredVault);
}

export async function createAutoStakerSafeTx(
  owner: SignerWithAddress,
  factory: OrigamiAutoStakingFactory,
  rewardVault: Address,
  performanceFeeBps: number
) {
  const infraredVault = IInfraredVault__factory.connect(rewardVault, owner);

  if ((await factory.swapperDeployer()) != ZERO_ADDRESS) {
    throw Error("Single-reward mode not handled yet");
  }

  return createSafeTransaction(
    factory.address,
    "registerVault",
    [
      {
        argType: "address",
        name: "asset_",
        value: await infraredVault.stakingToken(),
      },
      {
        argType: "address",
        name: "rewardsVault_",
        value: infraredVault.address,
      },
      {
        argType: "uint256",
        name: "performanceFeeBps_",
        value: performanceFeeBps.toString(),
      },
      {
        argType: "address",
        name: "overlord_",
        value: ZERO_ADDRESS,
      },
      {
        argType: "address[]",
        name: "expectedSwapRouters_",
        value: "[]", // No routers as in multi rewrd mode.
      },
    ],
  );
}
