import { ethers, network, upgrades } from "hardhat";
import { BaseContract, BigNumber, Contract, ContractFactory, ContractTransaction } from "ethers";
import { getImplementationAddress, ProxyKindOption } from '@openzeppelin/upgrades-core';
import { isAddress } from "ethers/lib/utils";

/**
 * Current block timestamp
 */
export const blockTimestamp = async () => {
  return (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
}

/** number to attos (what all our contracts expect) */
export function toAtto(n: number): BigNumber {
  return ethers.utils.parseEther(n.toString());
}

/** number from attos (ie, human readable) */
export function fromAtto(n: BigNumber): number {
  return Number.parseFloat(ethers.utils.formatUnits(n, 18));
}

export async function mine(tx: Promise<ContractTransaction>) {
  console.log(`Mining transaction: ${(await tx).hash}`);
  await (await tx).wait();
}
const { AddressZero } = ethers.constants;

/**
 * Typesafe helper that works on contract factories to create, deploy, wait till deploy completes
 * and output useful commands to setup etherscan with contract code
 */
export async function deployAndMine<T extends BaseContract, D extends (...args: any[]) => Promise<T>>(
  name: string,
  factory: ContractFactory,
  deploy: D,
  ...args: Parameters<D>): Promise<T> {

  if (factory.deploy !== deploy) {
    throw new Error("Contract factory and deploy method don't match");
  }

  // Ensure none of the args are empty
  args.forEach((a,i) => {
    if (!(a.toString()))
      throw new Error(`Empty arg in position ${i}`);
  });

  const renderedArgs: string = args.map(a => a.toString()).join(' ');

  console.log(`*******Deploying ${name} on ${network.name} with args ${renderedArgs}`);
  const contract = await factory.deploy(...args) as T;
  console.log(`Deployed... waiting for transaction to mine: ${contract.deployTransaction.hash}`);
  console.log();
  await contract.deployed();
  console.log('Contract deployed');
  console.log(`${name}=${contract.address}`);
  console.log(`export ${name}=${contract.address}`);
  console.log(`yarn hardhat verify --network ${network.name} ${contract.address} ${renderedArgs}`);
  console.log('********************\n');

  return contract;
}

interface Initializable extends Contract {
  initialize(...args: any[]): Promise<ContractTransaction>;
}

export async function deployProxyAndMine<T extends Initializable, D extends (...args: any[]) => Promise<T>>(
  existingProxyAddress: string | undefined,
  name: string,
  kind: ProxyKindOption['kind'],
  factory: ContractFactory,
  deploy: D,
  ...args: Parameters<T['initialize']>): Promise<T> {

  if (factory.deploy !== deploy) {
    throw new Error("Contract factory and deploy method don't match");
  }

  // Ensure none of the args are empty
  args.forEach((a,i) => {
    if (!(a.toString()))
      throw new Error(`Empty arg in position ${i}`);
  });

  const renderedArgs: string = args.map(a => a.toString()).join(' ');

  let contract: T;
  if (network.name != "localhost" && existingProxyAddress && isAddress(existingProxyAddress)) {
    console.log(`*******UPGRADING ${name} on ${network.name} and initializing with args ${renderedArgs}`);
    const oldImplAddress = await getImplementationAddress(ethers.provider, existingProxyAddress);
    console.log(`Old implementation address: ${oldImplAddress}`);
    contract = await upgrades.upgradeProxy(existingProxyAddress, factory, {kind}) as T;
  } else {
    console.log(`*******DEPLOYING upgradeable ${name} on ${network.name} and initializing with args ${renderedArgs}`);
    contract = await upgrades.deployProxy(factory, args, {kind}) as T; 
  }

  console.log(`... waiting for transaction to mine: ${contract.deployTransaction.hash}`);
  console.log();
  await contract.deployed();
  console.log('Contract deployed/upgraded');
  const newImplAddress = await getImplementationAddress(ethers.provider, contract.address);
  console.log(`New implementation address: ${newImplAddress}`);

  console.log(`${name}=${contract.address}`);
  console.log(`export ${name}=${contract.address}`);
  // Hardhat will verify the underlying, and then the proxy and then link them together
  // No args since their passed into initialize() instead of the constructor.
  console.log(`yarn hardhat verify --network ${network.name} ${contract.address}`);
  console.log('********************\n');

  return contract;
};

/**
 * Check if process.env.MAINNET_ADDRESS_PRIVATE_KEY (required when doing deploy)
 */
export function expectAddressWithPrivateKey() {
  if (network.name == 'mainnet' && !process.env.MAINNET_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable MAINNET_ADDRESS_PRIVATE_KEY. A mainnet address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'arbitrum' && !process.env.ARBITRUM_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable ARBITRUM_ADDRESS_PRIVATE_KEY. A mainnet arbitrum address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'avalanche' && !process.env.AVALANCHE_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable AVALANCHE_ADDRESS_PRIVATE_KEY. A mainnet avalanche address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'rinkeby' && !process.env.RINKEBY_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable RINKEBY_ADDRESS_PRIVATE_KEY. A rinkeby address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'goerli' && !process.env.GOERLI_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable GOERLI_ADDRESS_PRIVATE_KEY. A goerli address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'polygonMumbai' && !process.env.MUMBAI_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable MUMBAI_ADDRESS_PRIVATE_KEY. A mumbai address private key with eth is required to deploy/manage contracts");
  }
}

const expectedEnvvars: { [key: string]: string[] } = {
  mainnet: ['MAINNET_ADDRESS_PRIVATE_KEY', 'MAINNET_RPC_URL', 'MAINNET_GAS_IN_GWEI'],
  arbitrum: ['ARBITRUM_ADDRESS_PRIVATE_KEY', 'ARBITRUM_RPC_URL', 'ARBITRUM_GAS_IN_GWEI'],
  avalanche: ['AVALANCHE_ADDRESS_PRIVATE_KEY', 'AVALANCHE_RPC_URL', 'AVALANCHE_GAS_IN_GWEI'],
  rinkeby: ['RINKEBY_ADDRESS_PRIVATE_KEY', 'RINKEBY_RPC_URL'],
  goerli: ['GOERLI_ADDRESS_PRIVATE_KEY', 'GOERLI_RPC_URL'],
  polygonMumbai: ['MUMBAI_ADDRESS_PRIVATE_KEY', 'MUMBAI_RPC_URL'],
  matic: ['MATIC_ADDRESS_PRIVATE_KEY', 'MATIC_RPC_URL'],
  localhost: [],
}

/**
 * Check if the required environment variables exist
 */
export function ensureExpectedEnvvars() {
  let hasAllExpectedEnvVars = true;
  for (const envvarName of expectedEnvvars[network.name]) {
    if (!process.env[envvarName]) {
      console.error(`Missing environment variable ${envvarName}`);
      hasAllExpectedEnvVars = false;
    }
  }

  if (!hasAllExpectedEnvVars) {
    throw new Error(`Expected envvars missing`);
  }
}

// Matches IOrigamiGmxEarnAccount.VaultType
export enum GmxVaultType {
    GLP = 0,
    GMX,
};
