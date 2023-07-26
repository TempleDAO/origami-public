import { ethers, network, upgrades } from "hardhat";
import { BaseContract, BigNumber, Contract, ContractFactory, ContractTransaction } from "ethers";
import { getImplementationAddress, ProxyKindOption } from '@openzeppelin/upgrades-core';
import { isAddress } from "ethers/lib/utils";
import axios from 'axios';
import { stringify as qsStringify } from 'qs';
import { OrigamiGmxRewardsAggregator } from "../../typechain";
import * as fs from 'fs';
import * as path from 'path';

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
export { AddressZero as ZERO_ADDRESS };

// BigNumber json serialization override, dump as string
Object.defineProperties(BigNumber.prototype, {
    toJSON: {
      value: function (this: BigNumber) {
        return this.toString();
      },
    },
});

function ensureDirectoryExistence(filePath: string) {
    var dirname = path.dirname(filePath);
    if (fs.existsSync(dirname)) {
      return true;
    }
    ensureDirectoryExistence(dirname);
    fs.mkdirSync(dirname);
}

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

  const renderedArgs = JSON.stringify(args, null, 2);

  console.log(`*******Deploying ${name} on ${network.name} with args ${renderedArgs}`);
  const contract = await factory.deploy(...args) as T;
  console.log(`Deployed... waiting for transaction to mine: ${contract.deployTransaction.hash}`);
  console.log();
  await contract.deployed();
  console.log('Contract deployed');
  console.log(`${name}=${contract.address}`);
  console.log(`export ${name}=${contract.address}`);

  const argsPath = `scripts/deploys/${network.name}/deploymentArgs/${contract.address}.js`;
  const verifyCommand = `yarn hardhat verify --network ${network.name} ${contract.address} --constructor-args ${argsPath}`;
  ensureDirectoryExistence(argsPath);
  let contents = `// ${network.name}: ${name}=${contract.address}`;
  contents += `\n// ${verifyCommand}`;
  contents += `\nmodule.exports = ${renderedArgs};`;
  fs.writeFileSync(argsPath, contents);

  console.log(verifyCommand);
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
  constructorArgs: unknown[] | undefined,
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

  const renderedConstructorArgs = constructorArgs ? JSON.stringify(constructorArgs, null, 2) : '[]';
  const renderedInitArgs = args ? JSON.stringify(args, null, 2) : '[]';

  let contract: T;
  if (network.name != "localhost" && existingProxyAddress && isAddress(existingProxyAddress)) {
    console.log(`*******UPGRADING ${name} on ${network.name}`);
    const oldImplAddress = await getImplementationAddress(ethers.provider, existingProxyAddress);
    console.log(`Old implementation address: ${oldImplAddress}`);
    contract = await upgrades.upgradeProxy(existingProxyAddress, factory, {kind, constructorArgs}) as T;
  } else {
    console.log(`*******DEPLOYING upgradeable ${name} on ${network.name} with constructor args ${renderedConstructorArgs} and initializing with args ${renderedInitArgs}`);
    contract = await upgrades.deployProxy(factory, args, {kind, constructorArgs}) as T; 
  }

  console.log(`... waiting for transaction to mine: ${contract.deployTransaction.hash}`);
  console.log();
  await contract.deployed();
  console.log('Contract deployed/upgraded');
  const newImplAddress = await getImplementationAddress(ethers.provider, contract.address);
  console.log(`New implementation address: ${newImplAddress}`);

  console.log(`${name}=${contract.address}`);
  console.log(`export ${name}=${contract.address}`);

  const argsPath = `scripts/deploys/${network.name}/deploymentArgs/${contract.address}.js`;
  const verifyCommand = `yarn hardhat verify --network ${network.name} ${contract.address} --constructor-args ${argsPath}`;
  ensureDirectoryExistence(argsPath);
  let contents = `// ${network.name}: ${name}=${contract.address}`;
  contents += `\n// ${verifyCommand}`;
  // Hardhat will verify the underlying, and then the proxy and then link them together
  // No args since their passed into initialize() instead of the constructor.
  contents += `\nmodule.exports = ${renderedConstructorArgs};`;
  fs.writeFileSync(argsPath, contents);

  console.log(verifyCommand);
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

  if (network.name == 'goerli' && !process.env.GOERLI_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable GOERLI_ADDRESS_PRIVATE_KEY. A goerli address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'polygonMumbai' && !process.env.MUMBAI_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable MUMBAI_ADDRESS_PRIVATE_KEY. A mumbai address private key with eth is required to deploy/manage contracts");
  }

  if (network.name == 'polygon' && !process.env.POLYGON_ADDRESS_PRIVATE_KEY) {
    throw new Error("Missing environment variable POLYGON_ADDRESS_PRIVATE_KEY. A mumbai address private key with eth is required to deploy/manage contracts");
  }
}

const expectedEnvvars: { [key: string]: string[] } = {
  mainnet: ['MAINNET_ADDRESS_PRIVATE_KEY', 'MAINNET_RPC_URL', 'MAINNET_GAS_IN_GWEI'],
  arbitrum: ['ARBITRUM_ADDRESS_PRIVATE_KEY', 'ARBITRUM_RPC_URL', 'ARBITRUM_GAS_IN_GWEI'],
  avalanche: ['AVALANCHE_ADDRESS_PRIVATE_KEY', 'AVALANCHE_RPC_URL', 'AVALANCHE_GAS_IN_GWEI'],
  goerli: ['GOERLI_ADDRESS_PRIVATE_KEY', 'GOERLI_RPC_URL'],
  polygonMumbai: ['MUMBAI_ADDRESS_PRIVATE_KEY', 'MUMBAI_RPC_URL'],
  polygon: ['POLYGON_ADDRESS_PRIVATE_KEY', 'POLYGON_RPC_URL'],
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

export type ZeroExQuoteParams = {
    sellToken: string,
    buyToken:  string,
    sellAmount: string ,
    priceImpactProtectionPercentage: number,
    enableSlippageProtection: boolean,
    slippagePercentage: number,
}

export type ZeroExQuoteResponse = {
   price: string
   guaranteedPrice: string
   estimatedPriceImpact: string
   to: string
   data: string
   value: string
   buyAmount: string
   sellAmount: string 
   expectedSlippage: string
}

export const zeroExQuote = async (network: string, quoteParams: ZeroExQuoteParams): Promise<ZeroExQuoteResponse> => {
    try {
        const fullUrl = `https://${network}.api.0x.org/swap/v1/quote?${qsStringify(quoteParams)}`;
        console.log(`zeroExQuote: ${fullUrl}`);
        const { data } = await axios.get<ZeroExQuoteResponse>(fullUrl);
        return data;
    } catch (error) {
        if (axios.isAxiosError(error)) {
            console.log(error.toJSON());
            throw error;
        } else {
            throw error;
       }
   }
}

const investQuoteTypes = 'tuple(address fromToken, uint256 fromTokenAmount, uint256 maxSlippageBps, ' +
    'uint256 deadline, uint256 expectedInvestmentAmount, uint256 minInvestmentAmount, bytes underlyingInvestmentQuoteData)';
const exitQuoteTypes = 'tuple(uint256 investmentTokenAmount, address toToken, uint256 maxSlippageBps, ' + 
    'uint256 deadline, uint256 expectedToTokenAmount, uint256 minToTokenAmount, bytes underlyingInvestmentQuoteData)';

export const encodeGlpHarvestParams = (params: OrigamiGmxRewardsAggregator.HarvestGlpParamsStruct): string => {
    const types = `tuple(${exitQuoteTypes} oGmxExitQuoteData, bytes gmxToNativeSwapData, ` +
        `${investQuoteTypes} oGlpInvestQuoteData, uint256 addToReserveAmountPct)`;
    return ethers.utils.defaultAbiCoder.encode(
        [types], 
        [params],
    );
}

export const encodeGmxHarvestParams = (params: OrigamiGmxRewardsAggregator.HarvestGmxParamsStruct): string => {
    const types = `tuple(bytes nativeToGmxSwapData, ${investQuoteTypes} oGmxInvestQuoteData, uint256 addToReserveAmountPct)`; 
    return ethers.utils.defaultAbiCoder.encode(
        [types], 
        [params],
    );
}
