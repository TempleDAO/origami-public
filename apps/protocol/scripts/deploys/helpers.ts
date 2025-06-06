import { ethers, network, upgrades } from "hardhat";
import { BaseContract, BigNumber, BigNumberish, Contract, ContractFactory, ContractTransaction } from "ethers";
import { getImplementationAddress, ProxyKindOption } from '@openzeppelin/upgrades-core';
import { isAddress } from "ethers/lib/utils";
import axios from 'axios';
import { stringify as qsStringify } from 'qs';
import { IOrigamiElevatedAccess, TokenPrices__factory, PendlePYLpOracle__factory, IPMarket__factory } from "../../typechain";
import * as fs from 'fs';
import * as path from 'path';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

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

function checkVar(chainName: string, varName: string): boolean {
  if (network.name == chainName && !(varName in process.env)) {
    console.log(`Missing environment variable ${varName}.`);
    return false;
  }
  return true;
}

const expectedEnvvars: { [key: string]: string[] } = {
  mainnet: ['MAINNET_ADDRESS_PRIVATE_KEY', 'MAINNET_RPC_URL'],
  arbitrum: ['ARBITRUM_ADDRESS_PRIVATE_KEY', 'ARBITRUM_RPC_URL', 'ARBITRUM_GAS_IN_GWEI'],
  avalanche: ['AVALANCHE_ADDRESS_PRIVATE_KEY', 'AVALANCHE_RPC_URL', 'AVALANCHE_GAS_IN_GWEI'],
  goerli: ['GOERLI_ADDRESS_PRIVATE_KEY', 'GOERLI_RPC_URL'],
  polygonMumbai: ['MUMBAI_ADDRESS_PRIVATE_KEY', 'MUMBAI_RPC_URL'],
  polygon: ['POLYGON_ADDRESS_PRIVATE_KEY', 'POLYGON_RPC_URL'],
  matic: ['MATIC_ADDRESS_PRIVATE_KEY', 'MATIC_RPC_URL'],
  sepolia: ['SEPOLIA_ADDRESS_PRIVATE_KEY', 'SEPOLIA_RPC_URL'],
  holesky: ['HOLESKY_ADDRESS_PRIVATE_KEY', 'HOLESKY_RPC_URL'],
  bartio: ['BARTIO_ADDRESS_PRIVATE_KEY', 'BARTIO_RPC_URL'],
  cartio: ['CARTIO_ADDRESS_PRIVATE_KEY', 'CARTIO_RPC_URL'],
  berachain: ['BERACHAIN_ADDRESS_PRIVATE_KEY', 'BERACHAIN_RPC_URL'],
  bepolia: ['BEPOLIA_ADDRESS_PRIVATE_KEY', 'BEPOLIA_RPC_URL'],
  anvil: [],
  localhost: [],
}

/**
 * Check if the required environment variables exist
 */
export function ensureExpectedEnvvars() {
  let hasAllExpectedEnvVars = true;
  for (const envvarName of expectedEnvvars[network.name]) {
    checkVar(network.name, envvarName);
    if (!process.env[envvarName]) {
      console.error(`missing envvar: ${envvarName}`);
      hasAllExpectedEnvVars = false;
    }
  }

  if (!hasAllExpectedEnvVars) {
    throw new Error(`Expected envvars missing`);
  }
}

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

export async function setExplicitAccess(contract: Contract, allowedCaller: string, fnNames: string[], value: boolean) {
  const access: IOrigamiElevatedAccess.ExplicitAccessStruct[] = fnNames.map(fn => {
      return {
          fnSelector: contract.interface.getSighash(contract.interface.getFunction(fn)),
          allowed: value
      }
  });
  await mine(contract.setExplicitAccess(allowedCaller, access));
}

type TokenPricesArg = string | boolean | BigNumberish;

const encodeFunction = (fn: string, ...args: TokenPricesArg[]): string => {
    const tokenPricesInterface = new ethers.utils.Interface(JSON.stringify(TokenPrices__factory.abi));
    return tokenPricesInterface.encodeFunctionData(fn, args);
}

// For local fork testing/impersonation in anvil
export async function impersonateAndFund(owner: SignerWithAddress, address: string) {
  await mine(owner.sendTransaction({
    to: address,
    value: ethers.utils.parseEther("0.1"),
  }));
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [address]);
  return provider.getSigner(address);
}

// For local fork testing/impersonation in anvil
export async function impersonateAndFund2(address: string) {
  const provider = new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545");
  await provider.send('anvil_impersonateAccount', [address]);
  await provider.send('anvil_setBalance', [address, ethers.utils.parseEther("1").toHexString()]);
  return provider.getSigner(address);
}

// Check the Pendle Oracle and increase the cardinality if required.
export async function updatePendleOracleCardinality(
  pendleOracleAddress: string,
  pendleMarketAddress: string,
  owner: SignerWithAddress,
  twapSecs: number,
): Promise<void> {
  const pendleOracle = PendlePYLpOracle__factory.connect(pendleOracleAddress, owner);
  const oracleState = await pendleOracle.getOracleState(pendleMarketAddress, twapSecs);
  console.log("Existing Oracle State:", oracleState);
  if (oracleState.increaseCardinalityRequired) {
    console.log("Increase cardinality required");
    const market = IPMarket__factory.connect(pendleMarketAddress, owner);
    await mine(market.increaseObservationsCardinalityNext(oracleState.cardinalityRequired));

    if (network.name == 'localhost') {
      const block = await ethers.provider.getBlock("latest");
      const newTs = block.timestamp + twapSecs;
      await ethers.provider.send("evm_setNextBlockTimestamp", [newTs]);
      await ethers.provider.send("anvil_mine", [1]);
    } else {
      console.log(`Sleeping for the twap [${twapSecs}] seconds...`);
      await new Promise((resolve) => setTimeout(resolve, twapSecs * 1_000));
    }

    console.log("New Oracle State:", await pendleOracle.getOracleState(pendleMarketAddress, twapSecs));
  }
}

export function runAsyncMain<T>(p: () => Promise<T>): void {
  p()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
}

export enum PriceType {
  SPOT_PRICE,
  HISTORIC_PRICE
}

export enum RoundingMode {
  ROUND_DOWN,
  ROUND_UP
}

export const encodedOraclePrice = (oracle: string, stalenessThreshold: number): string => encodeFunction("oraclePrice", oracle, stalenessThreshold);
export const encodedUniV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("univ3Price", pool, inQuotedOrder);
export const encodedKodiakV3Price = (pool: string, inQuotedOrder: boolean): string => encodeFunction("kodiakV3Price", pool, inQuotedOrder);
export const encodedKodiakIslandPrice = (island: string): string => encodeFunction("kodiakIslandPrice", island);
export const encodedBalancerV2BptPrice = (balancerVault: string, bptToken: string): string => encodeFunction("balancerV2BptPrice", balancerVault, bptToken);
export const encodedMulPrice = (v1: string, v2: string): string => encodeFunction("mul", v1, v2);
export const encodedDivPrice = (numerator: string, denominator: string): string => encodeFunction("div", numerator, denominator);
export const encodedAliasFor = (sourceToken: string): string => encodeFunction("aliasFor", sourceToken);
export const encodedRepricingTokenPrice = (repricingToken: string): string => encodeFunction("repricingTokenPrice", repricingToken);
export const encodedErc4626TokenPrice = (vault: string): string => encodeFunction("erc4626TokenPrice", vault);
export const encodedTokenizedBalanceSheetTokenPrice = (vault: string): string => encodeFunction("tokenizedBalanceSheetTokenPrice", vault);
export const encodedWstEthRatio = (stEthToken: string): string => encodeFunction("wstEthRatio", stEthToken);
export const encodedOrigamiOraclePrice = (oracleAddress: string, priceType: PriceType, roundingMode: RoundingMode): string => 
  encodeFunction("origamiOraclePrice", oracleAddress, priceType, roundingMode);
export const encodedScalar = (amount: BigNumberish): string => encodeFunction("scalar", amount);
export const encodedTokenPrice = (token: string): string => encodeFunction("tokenPrice", token);
