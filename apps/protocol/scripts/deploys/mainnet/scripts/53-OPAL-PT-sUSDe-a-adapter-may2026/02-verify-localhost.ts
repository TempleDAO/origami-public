import { ethers } from 'hardhat';
import {
  runAsyncMain,
} from '../../../helpers';
import { ContractInstances } from '../../contract-addresses';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { getDeployContext } from '../../deploy-context';
import { IERC20Metadata__factory, IOpalAdapterAaveV3__factory, OpalManager, OpalManager__factory, OpalVault } from '../../../../../typechain';

let INSTANCES: ContractInstances;
let OPAL_INSTANCES: OpalContracts;
let TOKENS: { assets: Token[], liabilities: Token[] };

interface OpalContracts {
  VAULT: OpalVault;
  MANAGER: OpalManager;
}

interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

const Token = {
  create: async (owner: SignerWithAddress, address: string): Promise<Token> => {
    const contract = IERC20Metadata__factory.connect(address, owner);
    const [symbol, decimals] = await Promise.all([
      contract.symbol(),
      contract.decimals(),
    ]);
    const t: Token = {
      address: contract.address,
      symbol,
      decimals,
    };
    return t;
  }
}

const getContracts = async (vault: OpalVault, owner: SignerWithAddress): Promise<OpalContracts> => {
  const [manager, [assetTokens, liabilityTokens]] = await Promise.all([
    vault.manager(),
    vault.tokens(),
  ]);
  if (assetTokens.length != 1) console.warn("Can only handle 1 asset for now - using first one");
  if (liabilityTokens.length != 1) console.warn("Can only handle 1 liability for now - using first one");

  return {
    VAULT: vault,
    MANAGER: OpalManager__factory.connect(manager, owner),
  };
}

async function getTokens(owner: SignerWithAddress) {
  const [aTokens, lTokens] = await OPAL_INSTANCES.VAULT.tokens();
  const assets = await Promise.all(aTokens.map((a) => Token.create(owner, a)));
  const liabilities = await Promise.all(lTokens.map((a) => Token.create(owner, a)));
  return {
    assets,
    liabilities
  };
}

async function dumpPrices() {
  const allTokens = [
    ...TOKENS.assets,
    ...TOKENS.liabilities
  ]
  const prices = await INSTANCES.CORE.TOKEN_PRICES.V4.tokenPrices([
    OPAL_INSTANCES.VAULT.address,
    ...allTokens.map((t) => t.address)
  ]);
  console.log("\nToken Prices:");
  console.log(`\t$${await OPAL_INSTANCES.VAULT.symbol()}:`, ethers.utils.formatUnits(prices[0], 30));
  allTokens.forEach((t, i) => {
    console.log(`\t$${t.symbol}:`, ethers.utils.formatUnits(prices[i+1], 30));
  });
}

async function dumpBalanceSheet(owner: SignerWithAddress) {
  const [
    totalSupply,
   ] = await Promise.all([
    OPAL_INSTANCES.VAULT.totalSupply(),
    OPAL_INSTANCES.VAULT.tokens(),
  ]);
  const [aBalances, lBalances] = await OPAL_INSTANCES.VAULT.balanceSheet();
  console.log(`\nTOTAL SUPPLY: ${ethers.utils.formatEther(totalSupply)}`);
  console.log("\nASSET BALANCES:");
  aBalances.forEach((bal, i) => console.log(`\t${TOKENS.assets[i].symbol}: ${ethers.utils.formatUnits(bal, TOKENS.assets[i].decimals)}`));
  console.log("LIABILITY BALANCES:");
  lBalances.forEach((bal, i) => console.log(`\t${TOKENS.liabilities[i].symbol}: ${ethers.utils.formatUnits(bal, TOKENS.liabilities[i].decimals)}`));
}

async function getSymbols(tokenAddrs: string[], owner: SignerWithAddress) {
  return Promise.all(tokenAddrs.map(token => IERC20Metadata__factory.connect(token, owner).symbol()));
}

async function dumpAdapterDetails(owner: SignerWithAddress) {
  const adapterAddrs = await OPAL_INSTANCES.MANAGER.adapters();
  const adapters = adapterAddrs.map(addr => IOpalAdapterAaveV3__factory.connect(addr, owner));

  console.log("\nADAPTERS:");
  for (const adapter of adapters) {
    const [
      implTypeAndVersion,
      description,
      [assetGroupIds, liabilityGroupIds],
      currentLtv,
      maxSafeLtv,
      liquidationLtv,
      healthFactor,
      maxLoanUtilizationRatioOnJoin,
      [assetAddrs, liabilityAddrs],
    ] = await Promise.all([
      adapter.implTypeAndVersion(),
      adapter.description(),
      adapter.groupIds(),
      adapter.currentLtv(),
      adapter.maxSafeLtv(),
      adapter.liquidationLtv(),
      adapter.healthFactor(),
      adapter.maxLoanUtilizationRatioOnJoin(),
      adapter.tokens(),
    ]);

    const [assetSymbols, liabilitySymbols] = await Promise.all([
      getSymbols(assetAddrs, owner),
      getSymbols(liabilityAddrs, owner),
    ]);

    console.log(`\t${implTypeAndVersion} ${description}`);
    console.log(`\t\taddress = ${adapter.address}`);
    console.log(`\t\tassets = ${assetSymbols}`);
    console.log(`\t\tliabilities = ${liabilitySymbols}`);
    console.log(`\t\tgroup IDs:`);
    assetGroupIds.forEach((gid, i) => console.log(`\t\t${assetSymbols[i]}: ${gid}`));
    liabilityGroupIds.forEach((gid, i) => console.log(`\t\t${liabilitySymbols[i]}: ${gid}`));
    console.log(`\t\tcurrent LTV = ${ethers.utils.formatEther(currentLtv)}`);
    console.log(`\t\tmax safe LTV = ${ethers.utils.formatEther(maxSafeLtv)}`);
    console.log(`\t\tliquidation LTV = ${ethers.utils.formatEther(liquidationLtv)}`);
    console.log(`\t\thealth factor = ${ethers.utils.formatEther(healthFactor)}`);
    console.log(`\t\tmax UR for join = ${ethers.utils.formatEther(maxLoanUtilizationRatioOnJoin)}`);
  }
}

async function main() {
  let owner: SignerWithAddress;
  ({owner, INSTANCES} = await getDeployContext(__dirname));
  OPAL_INSTANCES = await getContracts(INSTANCES.VAULTS.OPAL_PT_SUSDE_A_DEPRECATED.TOKEN, owner);
  TOKENS = await getTokens(owner);

  await dumpPrices();
  await dumpBalanceSheet(owner);
  await dumpAdapterDetails(owner);
}

runAsyncMain(main);
